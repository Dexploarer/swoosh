---
name: xcodegen-roundtrip
description: How to regenerate the Xcode project from project.yml and which build command to use for each target. Use when editing project.yml, adding a target, changing signing/entitlements, building the menu-bar app, the widget extension, or the iOS app. Encodes simulator vs device flags and the GY5597YK9P signing setup.
---

# Xcode project roundtrip

`Swoosh.xcodeproj` is **generated** from `project.yml`. Never edit `.xcodeproj` files directly — changes will be clobbered on next `xcodegen generate`.

## When you must regenerate

- After **any** edit to `project.yml`.
- After adding new files to `App/`, `Apps/SwooshMac/`, `Apps/SwooshiOS/`, or `WidgetExtension/` that should be included in an Xcode-managed target. (SwiftPM-tracked sources under `Sources/` don't need regeneration.)
- After changing signing, entitlements, or build settings.

```bash
xcodegen generate
```

## Build commands per target

```bash
# Library / CLI / daemon — SwiftPM, no Xcode
swift build
swift build -c release

# Menu-bar macOS app
xcodebuild -project Swoosh.xcodeproj -scheme Swoosh \
  -destination 'platform=macOS' build

# Widget extension
xcodebuild -project Swoosh.xcodeproj -scheme SwooshWidgetExtension build

# iOS — simulator (signing auto via team GY5597YK9P)
xcodebuild -project Swoosh.xcodeproj -scheme SwooshiOS \
  -destination 'generic/platform=iOS Simulator' build

# iOS — physical device (uses team GY5597YK9P + cached provisioning profile)
xcodebuild -project Swoosh.xcodeproj -scheme SwooshiOS \
  -destination 'generic/platform=iOS' build
```

## Signing facts (don't re-derive these)

- `DEVELOPMENT_TEAM` = `GY5597YK9P` (Apple Development: <dexploarer@gmail.com>), set in `project.yml`.
- iOS bundle ID: `ai.swoosh.app.ios`.
- The matching provisioning profile is already in `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`. **Do not** re-download or re-create unless Xcode complains it's expired.
- macOS app sandbox is **disabled** for both the app and widget (`ENABLE_APP_SANDBOX: false`); app group is `group.ai.swoosh.shared`. Don't add a sandbox entitlement without discussing.

## Pitfalls

- **Editing `project.pbxproj` directly.** Survives until the next `xcodegen generate`, then vanishes. Always edit `project.yml`.
- **Skipping `xcodegen generate` after `project.yml` edit.** Xcode loads stale settings; the failure is silent (wrong target product, missing source file).
- **`CODE_SIGNING_ALLOWED=NO` on device builds.** Only useful for sim — device builds need the real signing path.
- **Running `xcodebuild` from a non-repo cwd.** Always run from `/Users/home/swoosh` (the `-project` path is repo-relative).
