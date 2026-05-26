#!/usr/bin/env bash
set -euo pipefail
# Reads Claude Code hook JSON from stdin when available. Also safe to run directly.
INPUT="$(cat || true)"
cmd="${INPUT}"
blocked=(
  "rm -rf /"
  "sudo rm -rf"
  "chmod -R 777"
  "security find-generic-password"
  "cat .env"
  "cat **/.env"
  "grep -R .*SECRET"
  "curl .*|.*sh"
  "wget .*|.*sh"
  "xcodebuild -allowProvisioningUpdates"
)
for pattern in "${blocked[@]}"; do
  if echo "$cmd" | grep -Eiq "$pattern"; then
    echo "BLOCKED by apple-agentic-swift hook: dangerous or secret-exposing command: $pattern" >&2
    exit 2
  fi
done
exit 0
