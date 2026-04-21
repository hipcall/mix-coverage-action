#!/usr/bin/env bash
# Parse the `mix test.coverage` / `mix test --cover` table.
# Accepts both pre-1.20 format (plain `Percentage | Module`) and the
# 1.20+ markdown-pipe format (`| Percentage | Module |`).
# Requires: bash 3.2+, sed, jq.

set -euo pipefail

: "${COVERAGE_PATH:?COVERAGE_PATH is required}"

if [ ! -r "$COVERAGE_PATH" ]; then
  echo "::error::Coverage file not found or unreadable: $COVERAGE_PATH" >&2
  exit 1
fi

# Leading and trailing pipes are optional: 1.20+ emits them, older Elixir does not.
# Module name excludes `|` so trailing pipes don't leak into the capture.
row_re='^[[:space:]]*\|?[[:space:]]*([0-9]+(\.[0-9]+)?)%[[:space:]]*\|[[:space:]]*([^|]*[^|[:space:]])[[:space:]]*\|?[[:space:]]*$'

total=""
modules_json='[]'
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
echo '[]' > "$tmp"

while IFS= read -r raw; do
  line=$(printf '%s\n' "$raw" | sed -E $'s/\x1b\\[[0-9;]*m//g')
  if [[ $line =~ $row_re ]]; then
    pct="${BASH_REMATCH[1]}"
    name="${BASH_REMATCH[3]}"
    if [ "$name" = "Total" ]; then
      total="$pct"
    else
      jq --arg p "$pct" --arg m "$name" '. + [{percentage: $p, module: $m}]' "$tmp" > "$tmp.new"
      mv "$tmp.new" "$tmp"
    fi
  fi
done < "$COVERAGE_PATH"

if [ -z "$total" ]; then
  echo "::error::No Total row found in coverage output. First 40 lines:" >&2
  head -40 "$COVERAGE_PATH" >&2
  exit 1
fi

modules_json=$(cat "$tmp")
result=$(jq -c -n --arg total "$total" --argjson mods "$modules_json" \
  '{total: $total, modules: $mods}')

echo "total-coverage=$total" >> "$GITHUB_OUTPUT"
{
  echo 'json<<MIX_COVERAGE_EOF'
  echo "$result"
  echo 'MIX_COVERAGE_EOF'
} >> "$GITHUB_OUTPUT"

count=$(jq 'length' <<< "$modules_json")
echo "Parsed total=${total}% across ${count} modules"
