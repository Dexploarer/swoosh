#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"
if [[ -f Package.swift && ! -d *.xcodeproj && ! -d *.xcworkspace ]]; then
  swift test
  exit $?
fi
workspace="$(find . -maxdepth 2 -name '*.xcworkspace' | head -n1 || true)"
project="$(find . -maxdepth 2 -name '*.xcodeproj' | head -n1 || true)"
if [[ -n "$workspace" ]]; then
  echo "Found workspace: $workspace"
  xcodebuild -list -workspace "$workspace"
  echo "Set SCHEME env var and rerun, e.g. SCHEME=AppName scripts/xcodebuild-test.sh"
  if [[ -n "${SCHEME:-}" ]]; then
    xcodebuild test -workspace "$workspace" -scheme "$SCHEME" -destination "platform=iOS Simulator,name=iPhone 16" | xcpretty || exit ${PIPESTATUS[0]}
  fi
elif [[ -n "$project" ]]; then
  echo "Found project: $project"
  xcodebuild -list -project "$project"
  echo "Set SCHEME env var and rerun, e.g. SCHEME=AppName scripts/xcodebuild-test.sh"
  if [[ -n "${SCHEME:-}" ]]; then
    xcodebuild test -project "$project" -scheme "$SCHEME" -destination "platform=iOS Simulator,name=iPhone 16" | xcpretty || exit ${PIPESTATUS[0]}
  fi
else
  echo "No Package.swift, .xcodeproj, or .xcworkspace found."
fi
