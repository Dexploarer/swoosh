---
name: swoosh-ios-boundary
description: Keep the Mac daemon and iPhone client boundary clean when changing Swoosh iOS support.
---
# Swoosh iOS Boundary Skill

Use this when changing `SwooshClient`, `SwooshAPI`, `SwooshDaemon`, or `Apps/SwooshiOS`.

## Instructions

1. Keep `SwooshClient` transport-only and free of Swoosh internal dependencies.
2. Do not import `SwooshKit` from the iOS app.
3. Keep the Mac daemon as the only `AgentKernel` owner.
4. Keep bearer auth required for all `/api/*` calls.
5. Verify iOS with:
   ```bash
   xcodebuild -project Swoosh.xcodeproj -scheme SwooshiOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
   ```
