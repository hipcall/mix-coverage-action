#!/usr/bin/env bash
# Evaluate coverage against configured thresholds.
# Emits a single `evaluation=<json>` line to $GITHUB_OUTPUT describing pass/fail,
# failures, threshold values, and (optionally) the changed-module subset.
# Requires: bash 3.2+, awk, jq.

set -euo pipefail

: "${PARSE_JSON:?PARSE_JSON is required}"

MIN_TOTAL="${MIN_TOTAL:-0}"
MIN_MODULE="${MIN_MODULE:-0}"
INCLUDE_CHANGED="${INCLUDE_CHANGED:-false}"
EVENT_NAME="${EVENT_NAME:-}"
CHANGED_FILES="${CHANGED_FILES:-}"

lt() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a+0 < b+0) }'; }
enabled() { lt 0 "$1"; }

total=$(jq -r '.total' <<< "$PARSE_JSON")
failures_json='[]'
changed_modules_json='[]'

append_failure() {
  failures_json=$(jq -c --arg kind "$1" --arg msg "$2" \
    '. + [{kind: $kind, message: $msg}]' <<< "$failures_json")
}

# 1. Total gate
if enabled "$MIN_TOTAL" && lt "$total" "$MIN_TOTAL"; then
  append_failure "total" "Total coverage ${total}% is below minimum ${MIN_TOTAL}%"
fi

# 2. Per-module gate (all modules)
if enabled "$MIN_MODULE"; then
  while IFS= read -r m; do
    [ -z "$m" ] && continue
    append_failure "module" "Module ${m} is below minimum ${MIN_MODULE}%"
  done < <(jq -r --arg min "$MIN_MODULE" \
    '.modules[] | select((.percentage|tonumber) < ($min|tonumber)) | .module' <<< "$PARSE_JSON")
fi

# 3. Changed-modules subset + optional gate
do_changed=false
if [ "$INCLUDE_CHANGED" = "true" ] && [ "$EVENT_NAME" = "pull_request" ]; then
  do_changed=true
fi

if [ "$do_changed" = "true" ]; then
  # Strip an optional path prefix ending in `lib/` (handles both
  # `apps/foo/lib/bar.ex` and `lib/bar.ex`) and the `.ex` suffix.
  changed_keys=$(printf '%s\n' "$CHANGED_FILES" \
    | { grep -E '\.ex$' || true; } \
    | sed -E 's|^(.*/)?lib/||; s|\.ex$||' \
    | sort -u)

  if [ -n "$changed_keys" ]; then
    mapfile -t all_modules < <(jq -r '.modules[].module' <<< "$PARSE_JSON")
    mapfile -t all_pcts    < <(jq -r '.modules[].percentage' <<< "$PARSE_JSON")

    for i in "${!all_modules[@]}"; do
      mod="${all_modules[$i]}"
      pct="${all_pcts[$i]}"
      underscored=$(printf '%s' "$mod" \
        | sed -E 's/([a-z0-9])([A-Z])/\1_\2/g' \
        | sed -E 's/([A-Z]+)([A-Z][a-z])/\1_\2/g' \
        | tr '[:upper:]' '[:lower:]' \
        | tr '.' '/')
      mod_basename="${underscored##*/}"
      while IFS= read -r key; do
        [ -z "$key" ] && continue
        key_basename="${key##*/}"
        # Strict: full-path or tail match. Falls back to basename match when
        # the filesystem doesn't mirror the module namespace (e.g. a flattened
        # lib/ layout where lib/account.ex defines MyApp.Datalayer.Account).
        if [ "$underscored" = "$key" ] \
            || [[ "$key" == */"$underscored" ]] \
            || [[ "$underscored" == */"$key" ]] \
            || [ "$key_basename" = "$mod_basename" ]; then
          changed_modules_json=$(jq -c --arg p "$pct" --arg m "$mod" \
            '. + [{percentage: $p, module: $m}]' <<< "$changed_modules_json")
          break
        fi
      done <<< "$changed_keys"
    done
  fi
fi

failure_count=$(jq 'length' <<< "$failures_json")
if [ "$failure_count" -eq 0 ]; then
  status="pass"
else
  status="fail"
fi

evaluation=$(jq -c -n \
  --arg status "$status" \
  --arg total "$total" \
  --argjson failures "$failures_json" \
  --argjson changed_modules "$changed_modules_json" \
  --arg min_total "$MIN_TOTAL" \
  --arg min_module "$MIN_MODULE" \
  --arg include_changed "$INCLUDE_CHANGED" \
  '{
    status: $status,
    total: $total,
    failures: $failures,
    changed_modules: $changed_modules,
    thresholds: {
      total: $min_total,
      module: $min_module
    },
    include_changed: ($include_changed == "true")
  }')

{
  echo 'evaluation<<MIX_COVERAGE_EOF'
  echo "$evaluation"
  echo 'MIX_COVERAGE_EOF'
} >> "$GITHUB_OUTPUT"

echo "Evaluation: status=${status}, failures=${failure_count}"
