#!/usr/bin/env bash
# Fetch the list of files changed in the current pull request.
# Requires: bash 3.2+, curl, jq.

set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${PR_NUMBER:?PR_NUMBER is required}"
: "${REPO:?REPO is required}"

files=""
page=1
while :; do
  resp=$(curl -sS \
    -H "Authorization: Bearer $GH_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/${REPO}/pulls/${PR_NUMBER}/files?per_page=100&page=${page}")

  if ! jq -e 'type == "array"' >/dev/null <<< "$resp"; then
    echo "::error::Unexpected response from GitHub API (page $page): $(jq -r '.message // "unknown"' <<< "$resp")" >&2
    exit 1
  fi

  count=$(jq 'length' <<< "$resp")
  [ "$count" -eq 0 ] && break
  files+=$(jq -r '.[] | select(.status != "removed") | .filename' <<< "$resp")$'\n'
  [ "$count" -lt 100 ] && break
  page=$((page + 1))
done

{
  echo 'files<<MIX_COVERAGE_EOF'
  printf '%s' "$files"
  echo 'MIX_COVERAGE_EOF'
} >> "$GITHUB_OUTPUT"

n=$(printf '%s' "$files" | grep -c . || true)
echo "Changed files in PR: ${n}"
