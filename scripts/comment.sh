#!/usr/bin/env bash
# Build a PR comment body from parsed coverage + evaluation, post or update it.
# Requires: bash 3.2+, curl, jq.

set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${PR_NUMBER:?PR_NUMBER is required}"
: "${REPO:?REPO is required}"
: "${PARSE_JSON:?PARSE_JSON is required}"
: "${EVALUATION:?EVALUATION is required}"

COMMENT_MODE="${COMMENT_MODE:-sticky}"
MARKER='<!-- mix-coverage-action:marker -->'

total=$(jq -r '.total' <<< "$PARSE_JSON")
status=$(jq -r '.status' <<< "$EVALUATION")
failure_count=$(jq '.failures | length' <<< "$EVALUATION")
min_total=$(jq -r '.thresholds.total' <<< "$EVALUATION")
min_module=$(jq -r '.thresholds.module' <<< "$EVALUATION")
include_changed=$(jq -r '.include_changed' <<< "$EVALUATION")

# Status line
if [ "$status" = "pass" ]; then
  status_line="✅ **All thresholds met**"
else
  status_line="❌ **${failure_count} threshold $( [ "$failure_count" = "1" ] && echo "violation" || echo "violations" )**"
fi

# Thresholds section (only show enabled ones)
thresholds_lines=""
[ "$(awk -v n="$min_total" 'BEGIN { exit !(n+0 > 0) }'; echo $?)" = "0" ] && \
  thresholds_lines+=$'\n'"- Minimum total: **${min_total}%**"
[ "$(awk -v n="$min_module" 'BEGIN { exit !(n+0 > 0) }'; echo $?)" = "0" ] && \
  thresholds_lines+=$'\n'"- Minimum module: **${min_module}%**"

thresholds_section=""
if [ -n "$thresholds_lines" ]; then
  thresholds_section=$'\n\n'"### Thresholds"$'\n'"${thresholds_lines}"
fi

# Failures section
failures_section=""
if [ "$failure_count" != "0" ]; then
  failures_md=$(jq -r '.failures[] | "- " + .message' <<< "$EVALUATION")
  failures_section=$'\n\n'"### Failures"$'\n\n'"${failures_md}"
fi

# Per-module table (collapsed)
module_count=$(jq '.modules | length' <<< "$PARSE_JSON")
modules_rows=$(jq -r '.modules[] | "| \(.percentage)% | \(.module) |"' <<< "$PARSE_JSON")

# Changed-files section
changed_section=""
if [ "$include_changed" = "true" ]; then
  changed_count=$(jq '.changed_modules | length' <<< "$EVALUATION")
  if [ "$changed_count" != "0" ]; then
    changed_rows=$(jq -r '.changed_modules[] | "| \(.percentage)% | \(.module) |"' <<< "$EVALUATION")
    changed_section=$'\n\n'"### Changed files (${changed_count})"$'\n\n'"| Percentage | Module |"$'\n'"|-----------:|:-------|"$'\n'"${changed_rows}"
  else
    changed_section=$'\n\n'"_No modules matched files changed in this PR._"
  fi
fi

body=$(printf '%s\n' \
  "$MARKER" \
  "## Mix Coverage" \
  "" \
  "${status_line}" \
  "" \
  "**Total:** ${total}%" \
)
body+="${thresholds_section}${failures_section}"
body+=$'\n\n'"<details><summary>Per-module coverage (${module_count})</summary>"$'\n\n'"| Percentage | Module |"$'\n'"|-----------:|:-------|"$'\n'"${modules_rows}"$'\n\n'"</details>"
body+="${changed_section}"

api() {
  curl -sS \
    -H "Authorization: Bearer $GH_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$@"
}

payload=$(jq -n --arg body "$body" '{body: $body}')

if [ "$COMMENT_MODE" = "sticky" ]; then
  existing=$(api "https://api.github.com/repos/${REPO}/issues/${PR_NUMBER}/comments?per_page=100" \
    | jq -r --arg marker "$MARKER" \
        '[.[] | select(.body | contains($marker))] | .[0].id // empty')
  if [ -n "$existing" ]; then
    api -X PATCH \
      "https://api.github.com/repos/${REPO}/issues/comments/${existing}" \
      -d "$payload" >/dev/null
    echo "Updated sticky comment #${existing}"
    exit 0
  fi
fi

api -X POST \
  "https://api.github.com/repos/${REPO}/issues/${PR_NUMBER}/comments" \
  -d "$payload" >/dev/null
echo "Created new coverage comment"
