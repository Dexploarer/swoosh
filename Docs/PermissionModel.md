# Swoosh Permission Model

Swoosh has two independent controls:

- `PermissionProfilePreset` decides which `SwooshPermission` cases the firewall grants.
- `ToolCallPolicy` and `SwooshSafetyConfig` decide whether the model may call tools, whether approvals are required, and whether normally gated capabilities are unlocked.

## Profiles

| Profile | Firewall grants | Tool policy | Safety flags |
|---------|-----------------|-------------|--------------|
| `safe` | Read-only runtime, memory, audit, and network status | Restrictive, low chain depth | Locked |
| `developer` | File, Git, Swift/Xcode, memory, workflow, skills, provider access, and `imageGenerate` | Default agent policy | Locked |
| `automation` | Developer plus calendar, reminders, scheduling, app usage, focus signals, account-delegation read, `videoGenerate`, `threeDGenerate` | Default agent policy | Locked |
| `power` | Nearly all permissions except mainnet writes (includes credential/auth inheritance and all media-gen) | Critical model calls allowed, approvals still required | Development safety |
| `trader` | Developer plus chain reads/builds/signing/broadcast and mainnet writes | Critical + human-only model calls allowed with approvals | Trader safety |
| `autonomous` | Every `SwooshPermission` case | Full model tool access, high limits, approvals optional | All safety flags enabled |
| `custom` | Developer defaults until edited | Default agent policy | Locked |

`autonomous` is intentional: it is the explicit opt-in for unattended agents that can run without human approval. Safe modes remain available and are still the default unless the user chooses otherwise.

## Runtime Policy Fields

`ToolCallPolicy` is enforced by the agent loop and registry:

| Field | Effect |
|-------|--------|
| `maxToolCallsPerTurn` | Total tool calls allowed in one turn |
| `maxToolChainDepth` | Maximum chained model tool-call depth |
| `allowModelToolCalls` | If false, the model receives no tool descriptors and returned tool calls are blocked |
| `allowHumanOnlyFromModel` | If false, human-only tools are hidden from and blocked for model-origin calls |
| `allowCriticalToolsFromModel` | If false, critical-risk tools are hidden from and blocked for model-origin calls |
| `requireApprovalForMediumRiskAndAbove` | If true, model-origin medium, high, and critical calls require approval even when a tool itself says `never` |

`SwooshSafetyConfig` gates advanced capabilities:

| Flag | Capability |
|------|------------|
| `autonomousTradingEnabled` | Autonomous trading workflows |
| `swapExecutionEnabled` | DEX swap execution |
| `portfolioRecommendationsEnabled` | Portfolio recommendation tools |
| `privateKeyCustodyEnabled` | Private-key custody in Keychain |
| `seedPhraseIngestionEnabled` | Seed phrase ingestion |
| `cookieIngestionEnabled` | Browser cookie ingestion |
| `shellToBlockchainBridgeEnabled` | Shell-to-wallet escalation path |
| `modelSelfApprovalEnabled` | Model-origin calls can bypass approval prompts |
| `mainnetWritesByDefault` | Mainnet write permissions can be granted by default |

## Surfaces

- Setup: `swoosh setup quick --permissions <safe|developer|automation|power|autonomous|custom>`.
- CLI status: `swoosh permissions --status` prints the active profile, tool policy, and key safety flags.
- macOS dashboard: Settings shows runtime config, every `ToolCallPolicy` field, and every `SwooshSafetyConfig` flag.
- iOS companion: Settings reads `/api/runtime/config` and shows the paired Mac daemon profile, tool policy, and safety flags.

## Media generation permissions

Four permissions gate the post-LLM media surface. Distinct cases let a user grant chat-with-images without also granting shell access or trading. The matching tool wrappers — `media.generate_image`, `media.generate_video`, `media.generate_3d`, `media.generate_music` — live in `SwooshToolsets` and register only when a matching provider is wired in `MediaGenDependencies` (the daemon constructs providers from Keychain keys via `MediaGenWiring`).

| Permission | Capability | Cloud requires |
|------------|------------|----------------|
| `imageGenerate` | Text-to-image. Local via Apple Image Playground (macOS 15.2+/iOS 18.2+), cloud via OpenAI `gpt-image-1`. | `networkAccess` for cloud |
| `videoGenerate` | Text-to-video. Cloud-only today via FAL.ai (Veo 3, Kling, Hunyuan Video). | `networkAccess` |
| `threeDGenerate` | Text/image-to-3D. Cloud-only today via FAL.ai (Tripo3D, Trellis, TripoSR). | `networkAccess` |
| `musicGenerate` | Text-to-music. Cloud-only today via Suno (sunoapi.org gateway), ElevenLabs Music, or Stable Audio. | `networkAccess` |

Local-only `imageGenerate` (Image Playground) is granted by `.developer`+. Cloud video, 3D, and music are granted by `.automation`+ since they imply outbound network spend. `media.generate_image` is `askFirstTime` (session-cacheable); the cloud-only video/3D/music tools are `askEveryTime` because every call materially spends API credit.

## Credential and auth inheritance permissions

These permissions gate local credential reuse during attended setup. They are granted by `power` and `autonomous`; lower presets require an explicit foreground onboarding or settings approval.

| Permission | Gates |
|------------|-------|
| `keychainCredentialsRead` | Reading compatible non-Swoosh Apple Keychain items after user consent. |
| `keychainCredentialsImport` | Copying discovered provider credentials into Swoosh's own Keychain namespace. |
| `browserCookiesRead` | Inspecting browser cookie stores or browser safe-storage availability after user consent. |
| `browserCookiesImport` | Reusing browser-cookie auth material through an explicit local inheritance flow. |

Credential values and cookie values never enter prompts or logs. Scout may derive reviewable setup recommendations from the presence of auth, but raw auth stays in the local credential path.

## Messaging and delegation permissions

These permissions gate attended setup for message connectors and separate user/agent identities.

| Permission | Gates |
|------------|-------|
| `messagesRead` | Reading local message metadata or connector-ready message stores after explicit approval. |
| `accountDelegationRead` | Inspecting configured user-vs-agent account roles. |
| `accountDelegationWrite` | Saving or changing which account an agent should use when acting as the user or as itself. |

`messagesRead` and delegation writes are granted by `power` and `autonomous`; `accountDelegationRead` is also granted by `automation` so setup surfaces can show the current role split without granting mutation. Message bodies, contact details, cookies, and secrets remain outside prompts unless they become user-approved memories.

## Approval Semantics

`askFirstTime` can be approved for the session. `askEveryTime` always creates a new approval request, even after a session approval. `humanOnly` blocks model-origin calls unless both the runtime tool policy and safety config explicitly opt into autonomous behavior.

Every tool call still passes through `SwooshFirewallActor`, is audited, and records approval state when approval is required.

## Plugin admin permissions

The plugin host (`SwooshPluginRuntime.PluginHost`) gates its lifecycle through four `humanOnly` admin permissions. None of them are ever requested by a plugin manifest — `PluginManifest.validate()` refuses any manifest that tries — and none of them can be invoked by the model. They exist so the user can explicitly opt into installing or running a plugin from the CLI or daemon API.

| Permission | Gates |
|------------|-------|
| `pluginInstall` | Adding a manifest to `~/.swoosh/plugins/`. Plugins start disabled after install. |
| `pluginUninstall` | Removing the plugin directory and dropping the manifest from the registry. |
| `pluginEnable` | Approving the plugin's requested permissions, granting them on the firewall, and bridging the plugin's tools into the `ToolRegistry`. |
| `pluginDisable` | Removing the plugin's tools from the registry and revoking any permissions only this plugin held (baseline grants and grants needed by other enabled plugins are preserved). |

Plugin **tools** declare ordinary `SwooshPermission` cases (`fileRead`, `networkAccess`, etc.) which the user grants when they enable the plugin. Each tool call still routes through `ToolRegistry.execute` → `firewall.require(descriptor.permission)`. There is no `pluginExecute` permission — the per-tool permission is the gate.

The user-facing surfaces for these admin permissions are `swoosh plugin {install,uninstall,enable,disable,list,status}` and the bearer-gated `/api/plugins/*` HTTP routes. The model has no path to either — these routes aren't reachable from inside an agent tool call, and the four admin permissions are excluded from any `PluginManifest.requestedPermissions` by `validate()` so a plugin can't grant itself the right to install other plugins.
