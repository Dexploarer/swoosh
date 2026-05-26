#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"
echo "== Apple Agentic Swift Doctor =="
echo "Root: $ROOT"
command -v xcodebuild >/dev/null && xcodebuild -version || echo "WARN: xcodebuild not found"
command -v swift >/dev/null && swift --version || echo "WARN: swift not found"
find . -maxdepth 3 \( -name '*.xcodeproj' -o -name '*.xcworkspace' -o -name Package.swift \) -print | sed 's#^./#- #'
find . -name PrivacyInfo.xcprivacy -print | sed 's#^./#privacy: #'
find . -name '*.entitlements' -print | sed 's#^./#entitlements: #'
find . -name '*AppIntent*.swift' -o -name '*Intent*.swift' | head -50 | sed 's#^./#intent: #'
find . -name '*Widget*.swift' -o -name '*LiveActivity*.swift' | head -50 | sed 's#^./#surface: #'
exit 0
