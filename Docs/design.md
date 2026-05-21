# Swoosh iOS — Design

How the Swoosh iPhone app looks, navigates, and connects. This is a
*descriptive* document: it records the design that ships in
`Apps/SwooshiOS/`, the reasoning behind it, and the research it draws
on. Update it when the design changes.

## 1. Goal

The iPhone is a **thin client** to `swooshd` (the Mac daemon that owns the
kernel, tools, providers, and ActantDB). The app's job is to make that
remote agent feel local: a fast chat surface, and a small set of
glanceable, drill-down surfaces for everything the agent *is* —
providers, channels, knowledge, runtime policy, media.

The chosen visual model is **Claude's own mobile app**. The agent
product the user already knows is Claude on iOS; mirroring its shell
means the app needs no onboarding to feel familiar.

## 2. Research basis — what we mirror

Patterns adopted from Anthropic's Claude iOS app and Apple's Human
Interface Guidelines:

| Pattern | Claude does it | Swoosh does it |
|---|---|---|
| **Chat is the only primary surface** | App opens straight into a full-bleed conversation, no tab bar | `RootView` → `ChatScreen` is the `NavigationStack` root |
| **Hamburger → left drawer** | Top-left button slides in a panel of recent chats + account | `SideDrawer`, 320 pt, `.thinMaterial`, scrim-to-dismiss |
| **Everything else is "behind" chat** | Settings/account live in the drawer, pushed as pages | Wallet / Connections / Settings are `DrawerDestination` pushes |
| **Asymmetric message treatment** | User turn is a bubble; assistant turn is plain flowing text | `ChatBubbleRow` — `.user` is a capsule, `.agent` is bare text |
| **Capsule composer** | Rounded input with attach + send affordances pinned to bottom | `ChatComposer` — 22 pt corner radius, circular send button |
| **Sectioned settings with icon tiles** | Grouped list, tinted rounded-square glyph per row | `IconTile` + `IconRow` across Connections & Settings |
| **Time-aware greeting / quick prompts** | Empty state greets the user and offers starters | `ChatScreen.emptyState` — greeting + suggested-prompt chips |

The **Channels** surface follows the [Chat SDK](https://chat-sdk.dev/)
model directly — Chat SDK is the upstream TypeScript SDK that
`SwooshChatSDK` ports, and the source of the `@chat-adapter/*`
packages. Its core concepts map 1:1 onto our UI:

| Chat SDK concept | Swoosh surface |
|---|---|
| **Adapters** (Slack, Teams, Discord, WhatsApp, GitHub, …) | platform-adapter rows, grouped by category |
| **State adapters** (Redis, Postgres, ActantDB, …) | "State backends" section |
| **Capabilities** (streaming, DMs, cards, modals) | the detail screen's "Capabilities" list |
| **Distribution** (internal / official / vendor / community) | the distribution pill on every row |

## 3. Shell architecture

```
SwooshiOSApp
└─ RootView                         NavigationStack(path:)
   ├─ ChatScreen                    stack root, nav bar hidden
   │  └─ navigationDestination(DrawerDestination)
   │       ├─ .wallet      → WalletScreen
   │       ├─ .connections → ConnectionsScreen
   │       └─ .settings    → SettingsScreen
   └─ SideDrawer (overlay)          slides over the stack
```

- **One `NavigationStack`**, rooted at `ChatScreen`. The system nav bar
  is hidden (`toolbar(.hidden, for: .navigationBar)`); `ChatScreen`
  draws its own `ChatTopBar` so the hamburger, title, and new-chat
  button match Claude's layout exactly.
- **The drawer is an overlay**, not a navigation destination — it
  slides in over whatever is on the stack. Selecting a row dismisses
  the drawer and `path.append`s a `DrawerDestination`.
- **Pushed surfaces use the standard nav bar.** Once you leave chat,
  the app behaves like a normal iOS settings hierarchy: large titles,
  back button, nested `NavigationLink` detail pushes.

This is the deliberate trade: chat gets a bespoke chrome; everything
else gets stock iOS so it's predictable and cheap to extend.

## 4. Navigation model

| From | Mechanism | To |
|---|---|---|
| Chat top bar hamburger | `drawerOpen = true` overlay | `SideDrawer` |
| Drawer row | `path.append(DrawerDestination)` | Wallet / Connections / Settings |
| Connections / Settings row | nested `NavigationLink` | detail screen |
| Channels row | nested `NavigationLink` | adapter detail + toggle |
| New chat | `ChatScreen.newChat()` | clears transcript in place |

Two depth levels under each drawer surface: **index → detail**. No
surface goes deeper. This keeps the back-stack shallow and legible.

## 5. Component system

Shared building blocks live in small files so every surface composes
the same vocabulary.

- **`IconTile`** — tinted rounded square (`tint.gradient`) with a
  centered SF Symbol. The unit of visual identity for a settings row.
- **`InitialsTile`** — monogram fallback (heavy rounded text on a solid
  fill) for brands without a bundled mark.
- **`IconRow`** — `IconTile` + title + optional one-line caption. The
  standard row in `ConnectionsScreen` / `SettingsScreen`.
- **`ProviderLogo` / `ChannelLogo` / `ChainLogo`** — look up a bundled,
  CC0 brand SVG in `Assets.xcassets` keyed by id; fall back to an
  `InitialsTile` monogram. White rounded plate behind each mark so
  dark logos stay legible in dark mode.
- **`StatusPill` / `DistributionPill`** (Channels) — small capsule
  badges: a tinted background at 18% opacity with a matching
  foreground. The same recipe used for the provider "Active" / "Ready"
  badges, factored into a reusable view.

### State components — `LoadingRow` / `ErrorRow`

Two shared building blocks back §7's loading and error states so they
read identically on every surface:

- **`LoadingRow`** — inline `ProgressView` + secondary label. Dropped
  into a `List` section or `LazyVStack` for "still loading" rows.
- **`LoadingState`** — full-bleed centered spinner + label for an
  otherwise-blank screen (first load with no cached data).
- **`ErrorRow`** — error `Label` with a trailing **Retry** button that
  re-runs the failed operation (`retry: (() async -> Void)?`). Used
  inside `List` / `Form` sections.
- **`ErrorBanner`** — free-standing rounded error banner with the same
  Retry affordance, for screens that show errors outside a `List`
  (the chat composer area, the wallet detail).

Every daemon call that can fail routes its error through `ErrorRow` /
`ErrorBanner` rather than static red text — error states are always
recoverable. The full-bleed "couldn't load" case uses
`ContentUnavailableView` with a `.borderedProminent` Retry button.

### Haptics

Key interactions emit haptics via SwiftUI `.sensoryFeedback`:
`.impact` on send, `.success` on pairing / account-create / key-save,
`.selection` on adapter toggle, `.error` on every surfaced failure.
Triggered off a monotonically-incremented counter so the feedback
fires once per event.

### Status & distribution colour language

| Meaning | Tint |
|---|---|
| Active / on / ready / healthy | green |
| Configured / informational | blue |
| Needs attention / missing key / unconfigured | orange |
| Blocked / error | red |
| Off / neutral / internal | secondary grey |
| Vendor distribution | purple · | Community distribution | teal |

## 6. Surface inventory

Every surface and what it is wired to. The iPhone speaks only
`SwooshClient` → `swooshd`; it never imports `SwooshKit`.

### Chat — `ChatScreen`
Three states: **empty** (greeting + suggested prompts), **thread**
(flat message stream, composer pinned), **unpaired** (prompt to open
Settings). Loads the transcript from `GET /api/agent/transcript/:id`;
sends through a `SwooshExecutor` → `POST /api/agent/chat`.

### Drawer — `SideDrawer`
Recent chats (the active session today) + the three surfaces. Footer
shows a live daemon-health dot (`ClientSession.lastHealth`).

### Connections — `ConnectionsScreen`
Sectioned index of what the agent *is*. Every row is wired to a live
daemon endpoint:

| Section | Row | Endpoint |
|---|---|---|
| Models | one row per provider | `GET /api/providers` |
| Channels | chat adapters | `GET /api/chat-adapters` |
| Knowledge | Skills · Memories | `GET /api/skills` · `/api/memories` |
| Runtime | Readiness & policy · Automations & goals | `GET /api/records` · `/api/runtime/config` |
| Media | Generated files | `GET /api/media` |

Provider detail can paste an API key (`POST /api/providers/auth`) and
set the preferred provider (`POST /api/providers/select`).

### Channels — `ChannelsScreen`
Live mirror of the daemon's chat-adapter catalog. Platform adapters are
grouped by category (Team chat, Direct messaging, Developer, …); state
backends get their own section. Each row shows real `enabled` /
`configured` status and a distribution pill. The detail screen lists
capabilities and missing credential env vars, and toggles the adapter
via `POST /api/chat-adapters/toggle`. When the phone is unpaired the
screen falls back to a static, read-only catalog (`ChannelCatalog`),
which also supplies category + description metadata the wire format
doesn't carry.

### Settings — `SettingsScreen`
Status header + **Daemon** (Pairing — host URL + bearer token paste,
the one form that bootstraps everything else) + **Agent** (Permission
profile → `POST /api/runtime/profile`; Safety flags →
`POST /api/runtime/flags`; Tool policy, read-only) + **About**.

### Wallet — `WalletScreen`
The exception to "thin client": an **on-device** multi-chain wallet.
Keys live in this iPhone's Keychain, Face ID-gated; balances are read
straight from public mainnet RPCs, no daemon round-trip. Distinct from
the agent's own trading capabilities, which stay on the Mac.

## 7. States

Every data surface handles four states explicitly, never a blank screen:

- **Unpaired** — `ContentUnavailableView` / inline prompt routing the
  user to Settings → Pairing.
- **Loading** — `ProgressView` + label, or `.refreshable` pull.
- **Error** — a red `Label` row carrying `error.localizedDescription`;
  never a crash, never a silent empty list.
- **Empty** — purposeful copy ("No reviewed skills loaded", "No
  generated files yet") rather than an empty container.

## 8. Visual language

- **Type** — system font. `.title3`/`.body` semibold for headers and
  row titles; `.caption`/`.caption2` secondary for detail lines;
  `.monospaced` for env vars, package names, and tokens.
- **Colour** — system semantic colours (`.background`,
  `.secondarySystemBackground`) so light/dark and accent tint are free.
  Accents are reserved for the status language in §5.
- **Materials** — `.regularMaterial` for the chat top bar and composer;
  `.thinMaterial` for the drawer panel; `.insetGrouped` lists everywhere
  else.
- **Shape** — continuous rounded rectangles: 22 pt composer, 18 pt user
  bubble, 14 pt suggested-prompt chips, 8–14 pt icon tiles.
- **Motion** — one easing curve, `easeOut` 0.22 s, for the drawer and
  message-append scroll. Restraint over flourish.

## 9. Data & trust boundary

- iOS imports **only `SwooshClient`** — wire types + a `URLSession`
  actor + Keychain/UserDefaults stores. It cannot import `SwooshKit`
  (which spawns subprocesses and won't build for iOS).
- All durable state — sessions, memories, approvals, audit, adapter
  toggles — lives on the Mac in ActantDB / `~/.swoosh/`. The phone
  caches nothing it can re-fetch.
- The bearer token is the only secret the phone stores, in the
  Keychain via `TokenStore`. Every `/api/*` call carries it.
- Wallet keys are the one piece of on-device custody, sealed in the
  Keychain and Face ID-gated — never sent to the daemon.

## 10. Deliberate non-goals (current slice)

Documented so they read as decisions, not gaps:

- Synchronous chat only — no token streaming yet.
- No Bonjour discovery — pairing is manual host + token.
- No on-device MLX path — the kernel is always the Mac.
- No approvals / audit UI on iOS — review happens on the Mac.
- Single chat thread — multi-session lands when the daemon's
  transcript API is split per-thread.
- The agent's own wallet / trading dashboard is not surfaced on the
  phone; the on-device wallet is a separate, simpler thing.

Each of these layers on without moving the client/server boundary.
