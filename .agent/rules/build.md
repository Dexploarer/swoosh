# Swoosh Build Rules

- Use `swift build` and `swift test` for SwiftPM library, CLI, daemon, and package verification.
- Use `xcodegen generate` after changing `project.yml`.
- Do not edit `Swoosh.xcodeproj` directly.
- Use `xcodebuild -project Swoosh.xcodeproj -scheme SwooshiOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` for iOS simulator verification.
- Do not add production dependencies without explicit user approval.
