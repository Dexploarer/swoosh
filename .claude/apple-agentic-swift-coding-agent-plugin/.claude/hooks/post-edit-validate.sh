#!/usr/bin/env bash
set -euo pipefail
# Fast validation after edits. Slow simulator builds should run via scripts/xcodebuild-test.sh or CI.
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"
if git diff --name-only -- '*.swift' | grep -q .; then
  echo "Swift files changed. Run: scripts/xcodebuild-test.sh or swift test"
fi
if git diff --name-only | grep -E 'PrivacyInfo\.xcprivacy|Info\.plist|\.entitlements|\.xcconfig' -q; then
  echo "Privacy/entitlement/build settings changed. Run: scripts/privacy-audit.sh"
fi
if git diff --name-only | grep -E 'AppIntent|Intent|Widget|AppClip|LiveActivity|FoundationModels' -q; then
  echo "System/agentic surface changed. Run: scripts/validate-agentic-apple.sh"
fi
exit 0
