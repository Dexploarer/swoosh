#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="${SWOOSH_LOCAL_SIGN_BUILD_ROOT:-$ROOT_DIR/.build/xcode-local-sign}"
PRODUCTS_DIR="$BUILD_ROOT/Debug"
APP_PATH="$PRODUCTS_DIR/Swoosh.app"
WIDGET_PATH="$PRODUCTS_DIR/SwooshWidgetExtension.appex"

IDENTITY="${SIGNING_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning | awk -F '"' '/Apple Development/ { print $2; exit }')"
fi

if [[ -z "$IDENTITY" ]]; then
  echo "No Apple Development signing identity found. Set SIGNING_IDENTITY or add an Apple ID in Xcode." >&2
  exit 1
fi

cd "$ROOT_DIR"

xcodebuild \
  -project Swoosh.xcodeproj \
  -scheme Swoosh \
  -destination 'platform=macOS' \
  SYMROOT="$BUILD_ROOT" \
  CODE_SIGNING_ALLOWED=NO \
  build

for bundle in "$WIDGET_PATH" "$APP_PATH"; do
  if [[ ! -d "$bundle" ]]; then
    echo "Expected build product missing: $bundle" >&2
    exit 1
  fi
done

while IFS= read -r binary; do
  codesign --force --timestamp=none --options runtime --sign "$IDENTITY" "$binary"
done < <(
  find "$APP_PATH/Contents/MacOS" "$WIDGET_PATH/Contents/MacOS" -type f -print |
    while IFS= read -r candidate; do
      if file "$candidate" | grep -q 'Mach-O'; then
        printf '%s\n' "$candidate"
      fi
    done
)

codesign \
  --force \
  --timestamp=none \
  --options runtime \
  --entitlements "$ROOT_DIR/WidgetExtension/SwooshWidgetExtension.entitlements" \
  --sign "$IDENTITY" \
  "$WIDGET_PATH"

codesign \
  --force \
  --timestamp=none \
  --options runtime \
  --entitlements "$ROOT_DIR/App/Swoosh.entitlements" \
  --sign "$IDENTITY" \
  "$APP_PATH"

codesign --verify --deep --strict --verbose=4 "$WIDGET_PATH"
codesign --verify --deep --strict --verbose=4 "$APP_PATH"

if spctl --assess --type execute --verbose=4 "$APP_PATH"; then
  echo "Gatekeeper assessment passed."
else
  echo "Gatekeeper assessment rejected this local development signature. Developer ID notarization still requires the paid Apple Developer Program."
fi

echo "Signed app: $APP_PATH"
