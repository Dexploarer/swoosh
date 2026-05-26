#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"
echo "== Privacy Audit =="
if ! find . -name PrivacyInfo.xcprivacy | grep -q .; then
  echo "WARN: No PrivacyInfo.xcprivacy found. Required for bundled privacy manifests when applicable."
fi
for key in NSCameraUsageDescription NSMicrophoneUsageDescription NSLocationWhenInUseUsageDescription NSPhotoLibraryUsageDescription NSSpeechRecognitionUsageDescription NSContactsUsageDescription NSCalendarsUsageDescription NSHealthShareUsageDescription; do
  if grep -R "$key" -n . --include='*.plist' --include='*.strings' >/dev/null 2>&1; then
    echo "permission: $key"
  fi
done
if grep -R "FoundationModels\|LanguageModelSession\|SystemLanguageModel" -n . --include='*.swift' >/dev/null 2>&1; then
  echo "AI: Foundation Models usage detected. Verify availability fallback, guardrail handling, and no raw transcript persistence."
fi
if grep -R "http://" -n . --include='*.swift' --include='*.plist' >/dev/null 2>&1; then
  echo "WARN: plaintext http:// references found; verify ATS/TLS requirements."
fi
exit 0
