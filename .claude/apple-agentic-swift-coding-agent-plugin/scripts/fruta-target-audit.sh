#!/usr/bin/env bash
set -euo pipefail
echo "== Fruta-style target audit =="
find . -maxdepth 4 \( -iname '*Clip*' -o -iname '*Widget*' -o -iname '*Intent*' -o -iname '*Shared*' \) -print | sed 's#^./#- #'
grep -R "AppGroup\|com.apple.security.application-groups\|group\." -n . --include='*.entitlements' --include='*.swift' || true
echo "Check manually: shared domain/services, extension-safe APIs, App Group justification, localization, StoreKit config, Sign in with Apple, PassKit/Apple Pay where relevant."
