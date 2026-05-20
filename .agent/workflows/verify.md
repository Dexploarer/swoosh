---
description: Build and test the Swift package before handing work back.
---

1. Run the package build:
   ```bash
   swift build
   ```
2. Run the package tests:
   ```bash
   swift test
   ```
3. If `project.yml` changed, regenerate the Xcode project:
   ```bash
   xcodegen generate
   ```
4. For iOS app changes, run the simulator build:
   ```bash
   xcodebuild -project Swoosh.xcodeproj -scheme SwooshiOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
   ```
