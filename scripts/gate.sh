#!/usr/bin/env bash
# Enforce coverage thresholds using precomputed evaluation. Exits 1 on failure.
# Requires: bash 3.2+, jq.

set -euo pipefail

: "${EVALUATION:?EVALUATION is required}"

status=$(jq -r '.status' <<< "$EVALUATION")
failed_modules=$(jq -c '[.failures[] | select(.kind == "module" or .kind == "changed-module") | .message]' <<< "$EVALUATION")

# Extract just the module names from messages for a cleaner output
failed_modules_names=$(jq -c '[.failures[] | select(.kind == "module") | .message | capture("^Module (?<m>[^ ]+)") | .m]' <<< "$EVALUATION")
echo "failed-modules=${failed_modules_names}" >> "$GITHUB_OUTPUT"

if [ "$status" = "pass" ]; then
  total=$(jq -r '.total' <<< "$EVALUATION")
  echo "Mix Coverage: all thresholds passed (total=${total}%)"
  exit 0
fi

echo "::error::Mix Coverage gate failed:"
jq -r '.failures[] | "  - " + .message' <<< "$EVALUATION"
exit 1
