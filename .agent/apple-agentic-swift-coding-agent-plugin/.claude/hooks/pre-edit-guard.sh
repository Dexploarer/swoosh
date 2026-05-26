#!/usr/bin/env bash
set -euo pipefail
INPUT="$(cat || true)"
# Conservative text scan. Agents with JSON payloads can adapt this to parse tool_input.file_path.
protected_patterns=(
  ".p12"
  ".mobileprovision"
  "AuthKey_.*\.p8"
  "GoogleService-Info.plist"
  ".env"
  "Secrets"
  "Production.xcconfig"
  "Release.xcconfig"
)
for pat in "${protected_patterns[@]}"; do
  if echo "$INPUT" | grep -Eiq "$pat"; then
    echo "BLOCKED by apple-agentic-swift hook: attempted edit may touch protected file pattern: $pat" >&2
    exit 2
  fi
done
exit 0
