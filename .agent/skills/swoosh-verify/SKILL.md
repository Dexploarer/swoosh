---
name: swoosh-verify
description: Verify Swoosh package, XcodeGen, and platform-specific build health before finalizing work.
---
# Swoosh Verification Skill

Use this when finishing code changes, reviewing a branch, or preparing a push.

## Instructions

1. Run `swift build`.
2. Run `swift test`.
3. If `project.yml` changed, run `xcodegen generate`.
4. If macOS app wiring changed, run:
   ```bash
   xcodebuild -project Swoosh.xcodeproj -scheme Swoosh -destination 'platform=macOS' build
   ```
5. If iOS app or `SwooshClient` wiring changed, run:
   ```bash
   xcodebuild -project Swoosh.xcodeproj -scheme SwooshiOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
   ```
