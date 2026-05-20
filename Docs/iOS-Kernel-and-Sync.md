# iOS-Local Kernel + Mac↔iPhone Sync — Design & Handoff

Status: design doc · 2026-05-19 · supersedes the "iPhone is always a thin
client" model from the initial iOS slice.

## What this is

The first iOS slice made the iPhone a thin HTTP client to `swooshd` on the
Mac. That gives us a shared agent identity but couples every iPhone chat
turn to "Mac is awake and reachable." This document is the plan to remove
that coupling: the iPhone gets its own embedded kernel and `ActantDB`,
and the two devices reconcile event logs over CloudKit so that:

- The iPhone can chat with full agent identity when the Mac is off,
  asleep, or out of network range.
- The Mac is preferred when reachable (bigger MLX models, full provider
  keys, real tools) — but never required.
- There is still one agent — both devices see the same memories, the
  same audit log, the same approvals.

Because we own both Swoosh and ActantDB, the work splits cleanly across
the two repos.

## The boundary

ActantDB ships the engine; Swoosh ships the agent. The contract between
them is the Swift SDK at `actantDB/sdks/swift/`. Today that SDK assumes
"talk to a remote Rust server over HTTP." The new shape:

```
            ┌──────────────────────────────────────────────────┐
            │  ActantDB Swift SDK (sdks/swift/)                │
            │  ─────────────────────────────────────────────── │
            │  Mode A: remote HTTP   (existing — Mac CLI/daemon)│
            │  Mode B: spawn local   (existing — swooshd boot)  │
            │  Mode C: embed via FFI (NEW — required for iOS)   │
            │  + sync primitives: events_since() / ingest()     │
            └──────────────────────────────────────────────────┘
                    ▲                          ▲
                    │                          │
            ┌───────┴──────┐            ┌──────┴───────┐
            │   Swoosh     │            │   Swoosh     │
            │   (macOS)    │            │   (iOS)      │
            │   Mode A or B│            │   Mode C only│
            └──────────────┘            └──────────────┘
                    \                       /
                     \                     /
                      \   CloudKit zone   /
                       \  (sync substrate)/
                        \________________/
```

Mode C is the new thing. CloudKit is the new thing on top. Everything
else is in place.

## ActantDB-side work (their repo)

### 1. FFI surface

The Rust core needs a Swift-callable interface that bypasses HTTP. Pick
one of:

- **`uniffi-rs`** *(recommended)* — Mozilla's binding generator. Mature,
  handles async, Swift errors, complex types. The procedural macro
  approach (`#[uniffi::export]`) keeps the FFI surface inline with the
  Rust code instead of in a separate IDL file.
- **`swift-bridge`** — more idiomatic Swift types, but younger and the
  async story is thinner.
- **Hand-rolled C-ABI** — fastest to start, hardest to maintain. Don't.

The surface should mirror what `ActantClient` already exposes over HTTP:
sessions, memories, audit, approvals, plus the new sync primitives below.

### 2. iOS-clean Rust core

Audit the Rust crates for assumptions that break inside an iOS sandbox:

- No `std::process::Command`, no spawning anything. (The supervisor stays
  on Mac/Linux; on iOS the SDK calls into the FFI directly.)
- No hard-coded `~/.actant` or `/tmp` paths — storage paths must be
  passed in from the Swift caller (iOS gives you an app-group container,
  not free filesystem access).
- Storage engine must be pure-Rust or rusqlite-bundled. If something
  links the system libsqlite, the iOS build will fail or behave
  unpredictably.
- No use of unblocked file APIs that iOS sandboxing rejects (most of
  `std::fs` is fine; specific gotchas: `chmod`, `mkfifo`, anything in
  `unix::fs::PermissionsExt`).

### 3. XCFramework packaging

The CI job ships an `XCFramework` containing static libs for
`aarch64-apple-ios`, `aarch64-apple-ios-sim`, `x86_64-apple-ios-sim`
(and the Mac slices if we also want Mode C on Mac for testing). Mirror
how the swift-nio / swift-crypto repos package binary releases — a
`.xcframework.zip` attached to a GitHub release, plus a checksum in
`Package.swift`:

```swift
.binaryTarget(
    name: "ActantDBCore",
    url: "https://github.com/Prompt-or-Die-Labs/actantdb/releases/download/x.y.z/ActantDBCore.xcframework.zip",
    checksum: "<sha256>"
)
```

### 4. Replication-friendly event shape

Every event in the log needs the following so two ledgers can be merged
without conflict:

- **Stable, content-derived event ID.** Hash of (kind, payload, actor,
  timestamp). Re-ingesting the same event is idempotent.
- **`actor_id`** — which device wrote this event. Persistent per
  install; derived from a UUID generated on first launch and stored in
  the user's iCloud Keychain so it survives reinstall.
- **HLC (Hybrid Logical Clock) timestamp.** Wall-clock plus a logical
  counter that increments per actor. Lets us order causally without
  trusting either device's clock fully.
- **Append-only by default.** Anything that looks like "update X" is
  modeled as a new event with a reference to the prior event ID.

### 5. Sync primitives

Two new SDK methods on top of the existing read/write surface:

```swift
// Pull all events strictly after a cursor. Cursor is an opaque token
// the caller stores. First call passes nil → "all events from the
// start of time."
func events(since cursor: SyncCursor?) async throws -> EventBatch

// Idempotent ingest. Events whose IDs already exist are silently
// skipped. Events are applied in causal (HLC) order, regardless of
// arrival order.
func ingest(_ events: [Event]) async throws -> IngestSummary
```

Both work in all three modes (remote / spawn / embed).

### 6. Conflict policy, documented

Append-only logs are merge-conflict-free by construction. State
projections built from those logs (e.g., "is this memory approved?",
"what is this approval's resolution?") need a documented rule. The
default should be **last-writer-wins by HLC**, applied per-record-type.
The SDK README should call this out explicitly so the agent layer
doesn't get surprises.

### 7. The trivial unblocker

```swift
#if os(macOS) || os(Linux)
// ActantDBSupervisor stays as-is
#endif
```

This one-liner around the existing supervisor file lets ActantDB's
Swift SDK build for iOS *today*, before any of the FFI work lands.
SwooshKit gets unblocked on iOS the moment this is in. The slice
plan can do it ahead of the bigger FFI lift.

## Swoosh-side work (this repo)

### 1. `SwooshExecutor` protocol — landed

The abstract chat backend now lives in `SwooshClient.SwooshExecutor`.
Two concrete implementations are in tree:

- `SwooshClient.RemoteKernelExecutor` — HTTP to a paired daemon.
- `SwooshKit.LocalKernelExecutor` — in-process `AgentKernel` wrapper
  (Mac/Linux only today).

The iOS app already routes through the protocol. The day actantDB
ships its iOS SDK, an iOS-buildable `LocalKernelExecutor` lands
alongside it and a `RoutedExecutor` picks "use Mac when reachable,
fall back to local" without touching `ChatView`.

### 2. `ToolPlatform` metadata — landed

`SwooshTool.platforms` (defaulting to `ToolsetID.defaultPlatforms`) plus
filtering in `ToolRegistry.register` ensure that on iOS, only tools
that claim `.iOS` get registered. The Files/Git/SwiftDev toolsets are
already tagged Mac-only at the toolset level.

### 3. `ActantSync` — pending

A new Swift module — *probably in actantDB's Swift SDK rather than
Swoosh*, since it's a general primitive — that watches the local
ledger for new events, publishes them to a CloudKit `CKPrivateDatabase`
zone, subscribes to remote changes, and ingests them back.

Sketch:

```swift
public actor ActantSync {
    init(local: ActantClient, zone: CKRecordZone.ID)

    func start()    // begin watching local + remote
    func stop()
    func sync()     // one-shot reconcile (for foreground triggers)
}
```

The local side calls `events(since:)` on a polling or change-notification
loop; CloudKit handles the remote push and pull via subscriptions. Each
event becomes one `CKRecord` with the event ID as `recordName`, so
CloudKit's per-record idempotency lines up with ours.

Open call: does this module live in `actantDB/sdks/swift/Sources/ActantSync/`
or in `Sources/SwooshSync/`? Argument for actantDB: it's a general
primitive for any app built on ActantDB. Argument for Swoosh: until
something else uses it, it's just Swoosh's sync layer. I'd default to
actantDB.

### 4. Provider routing on iOS — pending

When the iOS kernel is the one running the turn, it needs to decide
where the model call goes:

1. **Apple Foundation Models** (on-device). Free, private, lower
   capability than frontier models. Default for casual chat.
2. **Proxy to Mac** when Mac is reachable. Reuses the existing HTTP
   path but redefines the contract: "run this *model call*, not this
   *agent turn*, on the Mac." Lets the iPhone get GPT-class quality
   when at home without ever holding the API key.
3. **Direct provider call** with keys synced via iCloud Keychain.
   Worth it only when neither (1) nor (2) suffices.

`SwooshProviders` already has a routing layer (`ProviderRouter`); the
iOS-specific work is adding a Mac-proxy provider that targets the
existing daemon endpoint and a routing policy that prefers (1)/(2) on
iOS.

### 5. CloudKit pairing — optional sweetener

Once both devices speak CloudKit, the manual bearer-token paste becomes
unnecessary: the Mac publishes a "presence" record (URL + rotating
token) into the shared private zone, and the iPhone reads it on first
launch. Same trust boundary (iCloud account), much better UX. Not
required for option-3 sync to work, but the natural follow-on.

## Storage location

The on-device `actantdb` file lives in the iOS app group container so
the widget extension (today on Mac, conceivably on iPhone tomorrow)
can read it.

```
group.ai.swoosh.shared/Documents/actantdb/
    ├── actantdb.db          # active ledger
    ├── sync-cursor.json     # last successful pull cursor
    └── actor.json           # device's persistent actor ID + HLC state
```

## Encryption

CloudKit private DB is already iCloud-encrypted in transit and at rest.
For an agent product that's still probably worth layering app-controlled
encryption on top — agent memories are sensitive enough that a future
iCloud account compromise shouldn't yield plaintext. Mechanism:

- Symmetric key generated on first launch on the first device.
- Stored in iCloud Keychain so the second device gets it automatically
  on pair.
- All `CKRecord` payloads encrypted with this key before upload; event
  IDs and minimal metadata (timestamps, actor) stay clear so CloudKit
  can still do incremental sync efficiently.

Tradeoff: app-controlled encryption means losing both devices = losing
the data, because Apple can't recover it. Acceptable for v1; we can
add an exportable keybackup later.

## Open decisions (please weigh in)

1. **FFI binding strategy.** uniffi vs swift-bridge vs hand-rolled.
   Default: uniffi.
2. **Where does `ActantSync` live.** In actantDB's Swift SDK or in
   Swoosh? Default: actantDB.
3. **Encryption layer on top of CloudKit.** Layer it from day one or
   defer until v2? Default: layer it.
4. **Mode C on Mac too.** Should the Mac eventually run the kernel
   in-process via FFI instead of spawning a subprocess? Faster, fewer
   moving parts, no port management. Default: yes, once Mode C is
   proven on iOS.

## Order of operations

The work breaks into chunks that can ship independently:

1. **Unblocker** (actantDB, 30 min): `#if !os(iOS)` around
   `ActantDBSupervisor`. `SwooshKit` now builds for iOS.
2. **Replication-ready events** (actantDB, ~1 week): HLC clocks,
   stable IDs, actor tagging, `events(since:)` / `ingest()` primitives.
   No FFI work yet — still HTTP only.
3. **Sync layer** (~3 days): `ActantSync` module + CloudKit zone +
   encryption layer. Mac↔Mac sync works first (test target).
4. **FFI + XCFramework** (actantDB, ~2 weeks): `uniffi-rs` annotations,
   build script, CI release artifact, `binaryTarget` in `Package.swift`.
5. **iOS-local kernel** (this repo, ~1 week): iOS-buildable
   `LocalKernelExecutor`, `RoutedExecutor`, on-device provider story
   (Apple Foundation Models default + Mac-proxy fallback).
6. **CloudKit pairing UX** (~2 days): replace manual token paste with
   presence records.

The first slice already has us through (1) plus most of the
infrastructure for (5)'s router. (2) is the next thing to pick up on
the actantDB side; (3) and (4) can run in parallel once (2) lands.
