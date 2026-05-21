# Apps/SwooshiOS

The iOS companion app. Loaded automatically when Claude edits here.

## The one rule that breaks the build

**Only import `SwooshClient`. Never import `SwooshKit`.**

`SwooshKit` pulls in `SwooshActantBackend` → `ActantAgent.ActantDBSupervisor` → `Foundation.Process`, which iOS doesn't have. The instant you add `import SwooshKit` here, the iOS build dies with a Process unavailable error. The architectural separation exists for exactly this reason.

If you need a type that lives in `SwooshKit`, the right move is to **promote it to `SwooshClient`** (cross-platform, zero internal deps). The wire format already does this: `ChatRequest`/`ChatResponse`/`APIErrorBody`/`APIVersion` live in `Sources/SwooshClient/WireTypes.swift` precisely so both sides import from one place.

## Pairing model

The iPhone is a thin HTTP client. The Mac (`swooshd`) owns the single `AgentKernel`. The iPhone never holds kernel state.

Settings is the pairing form: host URL + bearer token paste. Token is stored in iOS Keychain via `TokenStore`. `SwooshAPIClient` (a `URLSession`-backed actor) posts to `/api/agent/chat`.

## Info.plist requirements

- `NSLocalNetworkUsageDescription` — required for any LAN traffic on iOS 14+.
- `NSBonjourServices=_swoosh._tcp` — for the future Bonjour discovery path.

Don't remove these even if discovery isn't wired yet.

## Current limits (deliberate)

- Synchronous chat only — no token streaming yet.
- No Bonjour discovery yet (host URL is pasted).
- No on-device MLX path.
- No approvals/audit UI.
- No remote-network story — assumes Mac and iPhone are on the same Wi-Fi.

All of these layer on without changing the client/server boundary. Don't bypass the boundary to deliver any of them faster.

## Build commands

```bash
xcodebuild -project Swoosh.xcodeproj -scheme SwooshiOS \
  -destination 'generic/platform=iOS Simulator' build   # sim, auto-signs with team GY5597YK9P
xcodebuild -project Swoosh.xcodeproj -scheme SwooshiOS \
  -destination 'generic/platform=iOS' build              # device, same team
```

Provisioning profile is already cached; bundle ID is `ai.swoosh.app.ios`.
