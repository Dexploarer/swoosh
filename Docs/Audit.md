# Swoosh — Readiness & Usefulness Audit

**Date:** 2026-05-20
**Method:** Five parallel auditor agents, one per subsystem slice, read-only
code inspection plus one cold `swift build` / full `swift test` run. Every
finding below is backed by `file:line` evidence in the source.

---

## 1. Executive summary

**Swoosh's core agent spine is real and works. Its advertised
differentiators are mostly unwired code.**

The setup → provider → chat → tools → persist → iPhone path is genuinely
implemented end to end: the daemon builds and runs, spawns ActantDB,
holds a real audited conversation against a live cloud model, executes a
useful set of developer tools behind a genuinely unbypassable firewall,
and serves a bearer-gated HTTP API that the iPhone app consumes. The
tree builds clean (0 errors) and 1030/1030 active tests pass.

But the features that make Swoosh *Swoosh* on paper — local
Apple-silicon (MLX) inference, the crypto toolsets, the self-improvement
pillars (Skills/Goals/Manifesting), and MCP interop — are present as
code but not connected to any runtime path. They compile; they do not
run.

| | Verdict |
|---|---|
| **Framework readiness** | **Beta** for the core spine; **Alpha → Prototype** for the differentiators |
| **Agent usefulness** | **Genuinely useful today** as a cloud-backed developer-loop assistant; **not yet useful** for local inference, crypto, autonomous self-improvement, or MCP |
| **Engineering quality (where wired)** | **High** — disciplined, typed, tested, zero `TODO`/`fatalError` in 57k LOC |
| **Documentation accuracy** | **Low** — README/CLAUDE.md materially overstate what is wired |

---

## 2. Subsystem scorecard

| Subsystem | Readiness | Useful today? | One-line status |
|---|---|---|---|
| Build & test health | Beta | — | Clean cold build; 1030 tests green; 18 test modules disabled |
| Agent kernel & tool loop | Beta | ✅ Yes | `AgentKernel.run` + `AgentToolLoop` fully real, no stubs |
| Model providers (cloud) | Beta | ✅ Yes | 4 real HTTP providers; router + fallback real |
| Model providers (local MLX / Foundation) | Prototype | ❌ No | Real code, **zero call sites** — unreachable |
| Tools — dev loop (files/git/swift/terminal/memory/scout/workflow) | Beta | ✅ Yes | ~50-55 genuinely functional registered tools |
| Tools — crypto (EVM/Solana/Jupiter/Hyperliquid/Uniswap) | Prototype | ❌ No | ~75 declared tools, **never registered**, no RPC client exists |
| Firewall & safety model | Beta | ✅ Yes | Unbypassable default-deny chokepoint; real `humanOnly`/trading gates |
| Audit & approvals durability | Alpha | ⚠️ Partial | Works in-memory only; **lost on daemon restart** |
| Scout (personalization) | Beta | ✅ Yes | Real pipeline + redactor + sources, wired and running |
| Cron | Beta | ✅ Yes | Real scheduler with a live 60s tick loop |
| Skills | Alpha | ⚠️ Partial | Real store + tools; prompt-catalog injection is dead code |
| Goals | Prototype | ❌ No | Real `GoalRunner` loop **invoked nowhere** |
| Manifesting ("dreaming") | Prototype | ❌ No | Real pipeline starved by an empty audit source |
| Flow (workflow engine) | Alpha | ❌ No | Substantial engines, **orphaned** — no tool/daemon wiring; `resume()` bug |
| Triggers | Prototype | ❌ No | Bare schema, no runner |
| Storage (ActantDB) | Beta | ✅ Yes | Real Rust sibling repo, built binary, daemon has run against it |
| Daemon | Beta | ✅ Yes | Genuinely wires kernel/providers/tools/API/cron/scout |
| HTTP API & client | Beta | ✅ Yes | ~25 endpoints, bearer auth, full client coverage |
| iOS app | Beta | ✅ Yes | Builds; thin client; all daemon surfaces reachable |
| MCP (Model Context Protocol) | Prototype | ❌ No | Registry/auth types only — **no transport**, cannot connect |
| Gateway / Bridge / Integrations | Prototype | ❌ No | Interfaces + no-op adapters; `SwooshBridge` is inert dead code |
| Observability | Prototype | ❌ No | 1036 LoC fully built, **zero importers** |
| Vault | Prototype | ❌ No | In-memory dict, no persistence (despite "SQLite" claim) |

---

## 3. What works today (the functional spine)

A user who runs `swooshd` on a Mac with an OpenAI or OpenRouter key in
the Keychain gets a real, working agent:

- **A real conversation.** `AgentKernel.run` executes all eight steps —
  load approved memories → build system prompt → merge transcript →
  call the model provider → persist → write an audit record — with no
  stubs (`AgentKernel.swift:371-432`). `AgentToolLoop` is a genuine
  model → tool → model loop with native tool-call parsing and per-turn
  limits (`AgentToolLoop.swift:156-328`).
- **Real model access.** Four `URLSession` HTTP providers
  (OpenAI Responses, OpenRouter incl. real PKCE, local OpenAI-compatible,
  Eliza Cloud) with proper request construction, SSE streaming, and
  error handling. `ProviderRouter` does real role-based routing with
  fallback chains.
- **A useful tool set.** ~50-55 registered, functional tools: read /
  write / search / patch files over approved roots, full git, Swift
  build/test/format, shell + docker/ssh execution, memory CRUD, the
  Scout pipeline, and workflow tools.
- **A safety model that is real, not aspirational.** `SwooshFirewallActor`
  is a true default-deny chokepoint — any permission not explicitly
  granted throws (`Firewall.swift:26-34`). Every registered tool call
  routes through `ToolRegistry` which checks toolset-enabled →
  `humanOnly` → trading-safety → policy → `firewall.require` → approval
  → audit before executing. `humanOnly` and trading-write gates are
  real and double-layered. A model cannot approve its own tool calls.
- **The privacy boundary holds.** `PromptBuilder` only ever sees
  `loadApprovedMemories()` — rejected candidates, raw Scout records,
  cookies, and secrets cannot structurally enter a prompt
  (`AgentKernel.swift:73-75, 239-309`).
- **Real persistence.** ActantDB is a genuine event-sourced sibling
  repo (`/Users/home/actantDB/`, a 39-crate Rust workspace) with a
  built binary. The daemon spawns `actantdb serve`, and
  `~/.swoosh/actant.db` (1.7 MB, recent writes) proves it has run
  end to end.
- **A working CLI and iPhone client.** `swoosh --help` / `swoosh doctor`
  work and exit clean; the bearer-gated HTTP API serves ~25 endpoints;
  the iOS app builds and reaches every daemon surface.
- **A disciplined surface.** The tree has been scrubbed of
  `TODO`/`FIXME`/`fatalError`/`unimplemented` markers — zero across 302
  files and ~57k LOC — and 1030/1030 active Swift-Testing cases pass
  plus 62 XCTest. Caveat: this is *marker* hygiene, not the absence of
  incomplete work. Semantic stubs do exist — functions that
  `throw .disabled`, return hardcoded `0x0`/`[]`, or throw
  `transportUnavailable` — they simply do not announce themselves with
  a comment. They are catalogued in §4.

---

## 4. What does not work (unwired, stubbed, or dead)

The recurring failure mode is **"last-mile wiring missing"**: a real
algorithm, store, or engine exists, but the call site that would
exercise it was never connected.

- **Local inference is unreachable.** `MLXInferenceEngine`
  (`SwooshMLX`) and `FoundationModelAdapter` (`SwooshFoundation`)
  contain real, non-stub code — but neither conforms to a provider
  protocol and **neither has a single call site**. The README's
  headline "MLX-capable, Apple-first" local-model story does not
  execute. The agent can only use cloud models.
- **The entire crypto surface is dead code.** ~75 declared tools
  across EVM, Solana, Jupiter, Hyperliquid, and Uniswap. EVM/Solana
  registration is guarded on an RPC client that **no code ever
  injects** (and no concrete client implementation exists); Jupiter,
  Hyperliquid, and Uniswap have **no registration hook at all**.
  Several "build transaction" tools are disguised stubs that produce
  empty, unsignable transactions (`EVMTools.swift:219`,
  `SolanaTools.swift:185`). The agent cannot do anything on-chain.
- **Audit & approvals are not durable.** Despite CLAUDE.md's "all
  durable state — sessions, memories, approvals, audit records — lives
  in ActantDB," the daemon constructs `SwooshAuditLog()` (in-memory)
  and `InMemoryApprovalStore()` (`Daemon.swift:1129-1131`). The audit
  trail and pending-approval queue **vanish on every `swooshd`
  restart** — breaking engineering rule #3 ("every agent step is
  logged") and rule #5 (`/why` audit inspection).
- **The self-improvement pillars do not self-improve.**
  - *Skills*: the store, trust gate, and four bundled `.md` skills are
    real, but the "Level-0 progressive disclosure" catalog is **never
    injected into a prompt** — both `buildSystemPrompt` call sites omit
    the `skillCatalog:` argument, so the injection block is dead. Skills
    reach the model only if it proactively calls `skill_list`.
  - *Goals*: `GoalRunner` has a real iteration loop, but
    `run(goalID:)` is **invoked by nothing** — no CLI command, no HTTP
    route, no background task. `goal_set` creates goals no loop advances.
  - *Manifesting*: the five-phase pipeline is real, but the daemon
    constructs the `Manifester` without an audit source, so it uses
    `EmptyManifestationAuditSource` → every scheduled pass gathers 0
    events and short-circuits to `.skipped`. There is also no path to
    promote a proposal into a skill or memory.
- **The workflow engine is orphaned.** `WorkflowExecutionEngine`,
  `DryRunEngine`, and `ReplayEngine` are substantial real code, but
  `SwooshFlow` exposes no tool surface and the daemon never wires them
  — they are reachable only from a SwiftUI dashboard pane.
  `resume()` has a silent correctness bug: `findLastApprovedGate`
  always returns `nil`, so a human-approved step is permanently
  skipped (`WorkflowExecutionEngine.swift:222-226`).
- **Cleanup note (2026-05-22):** the previously flagged unused
  observability package, trigger-schema package, and compile-time tool
  macro have been deleted from the SwiftPM source/test graph. The
  remaining breadth risk is now live experimental surface area, not
  dormant package targets.
- **18 test modules are switched off.** Their files are renamed
  `.swift.disabled` — ~655 tests across exactly the riskiest modules
  (firewall, goals, manifesting, toolsets, vault, sandbox, MLX,
  observability, …). The safety net is off where it matters most.
- Trigger scheduling now routes through the cron/workflow surfaces that
  still have live importers.

---

## 5. Claims vs. reality

The README and `CLAUDE.md` describe a system materially more complete
than the one in the tree. Documentation should be reconciled:

| Doc claims | Reality |
|---|---|
| "MLX-capable, Apple-first" local model runtime | `SwooshMLX`/`SwooshFoundation` compile but have no call sites |
| Crypto toolsets (EVM/Solana/Jupiter/Hyperliquid/Uniswap) | Declared but never registered; partly stubbed; no RPC client |
| "All durable state — … approvals, audit records — lives in ActantDB" | Audit + approvals are in-memory; lost on restart |
| "`SwooshVault` … uses `SQLite.swift` … for local caches" | `MemoryVault` is a plain in-memory dictionary, no persistence |
| "Level-0 progressive disclosure" skill catalog injection | The injection code path is dead (argument never passed) |
| Scout `MusicHistorySource` / `ScreenTimeSource` scaffolds | Neither type exists in the codebase |
| Compile-time tool generation macro | Removed; tools hand-write typed conformance |
| README quick-start (`FileReadTool()`, `ShellTool()` no-arg) | Real tools require `ToolDependencies` injection |
| OpenAI / OpenRouter / Eliza Cloud / local adapters | Current provider set is Codex bridge, OpenAI, OpenRouter, Eliza Cloud, MLX local, Apple Foundation Models, and local OpenAI-compatible |
| "Every workflow is replayable / trigger-dispatched" | No live entry point; replay re-runs tools rather than a recorded trace |

---

## 6. Cross-cutting patterns

1. **Spine deep, wings wide.** Effort concentrated correctly on the
   path that has to work — kernel, providers, firewall, daemon,
   persistence — and that path is genuinely solid. The breadth modules
   were built as code but never connected.
2. **"Last-mile wiring" is the dominant defect class.** GoalRunner
   never invoked, skill catalog never passed, Manifester fed an empty
   source, Flow orphaned, local inference once unwired, crypto never
   registered. The fixes are often small
   (a missing argument, a missing `register*` hook) but they are the
   difference between "feature" and "dead code."
3. **Quality where wired is high — but "no markers" ≠ "no stubs".**
   Default-deny firewall, structural privacy boundary, typed tools,
   1030 passing tests. The tree carries zero `TODO`/`fatalError`
   markers, but that is marker hygiene: the incomplete code is real
   (hardcoded returns, `throw .disabled`, `transportUnavailable`) — it
   is just *quiet* rather than flagged. This is not a sloppy codebase;
   it is an *overscoped* one whose unfinished edges do not advertise
   themselves, which makes an audit like this one necessary to find
   them.
4. **The docs are ahead of the code.** The README reads as a finished
   product; the tree is a strong core with a wide ring of prototypes.
5. **Test coverage is inverted.** The modules with the most disabled
   tests (firewall, goals, manifesting, toolsets, vault) are the ones
   carrying the most safety-critical or most-incomplete logic.

---

## 7. Prioritized recommendations

**P0 — restore the safety net and honour the durability contract**
- Re-enable the 18 `.swift.disabled` test modules (or delete them
  honestly). Today firewall, goals, manifesting, toolsets, and vault
  ship with no executing tests.
- Make audit records and approvals durable via ActantDB, as the docs
  already claim. This is a correctness bug, not a feature gap — it
  breaks engineering rules #3 and #5.

**P1 — fix the bugs in code that is supposed to work**
- `ProviderRouter.testProvider` probes with `model: ""`
  (`ProviderRouter.swift:185`) — real APIs reject this, so health
  checks mis-report working providers as unreachable.
- `WorkflowExecutionEngine.resume()` permanently skips the
  human-approved step (`findLastApprovedGate` always `nil`).
- `swooshd --help` starts the daemon instead of printing help.

**P1 — pick the headline differentiator and actually wire one**
- Choose **one** of: MLX local inference, the crypto surface, or the
  self-improvement loop — and complete its last-mile wiring so it runs.
  Shipping one real differentiator beats three prototypes.
- Lowest effort, highest narrative payoff is usually **Skills**: pass
  `skillCatalog:` to `buildSystemPrompt` and the documented behaviour
  starts working.
- **Goals** needs only a runner entry point (a CLI command or daemon
  task calling `GoalRunner.run`).

**P2 — reconcile the documentation with the tree**
- Update README/CLAUDE.md so every claim maps to wired code, or move
  unwired modules into an explicit "experimental / not yet wired"
  section. The current gap will mislead contributors and users.

**P2 — keep deleting dormant package targets**
- The unused observability, trigger-schema, browser/media/sandbox/gateway,
  installer/setup/LSP/integration, worker, and compile-time macro targets
  were removed on 2026-05-22 after reference-graph and build verification.
  Keep future package targets tied to a live importer or delete them.

**Packaging**
- The storage path depends on a hand-built **debug** `actantdb` binary
  in `~/.cache/`. A clean machine has no artifact and the daemon
  `exit(1)`s. Ship a release binary or document the `cargo build` /
  `SWOOSH_ACTANTDB_PATH` bootstrap step.

---

## 8. Bottom line

Swoosh is a **well-engineered Beta core wrapped in a wide ring of
Alpha/Prototype features**. The agent it actually ships today is real
and genuinely useful: a private, auditable, cloud-backed developer
assistant with a strong permission model and a clean Mac↔iPhone split.
That is a credible product.

What it is *not* — yet — is the "MLX-capable, Apple-first, crypto-native,
self-improving" runtime the documentation describes. Those features are
written but not plugged in. The good news is that the gap is mostly
wiring, not missing implementation: the hard parts (engines, stores,
algorithms) largely exist. The path to "ready" is to **finish the last
mile on a chosen few, switch the tests back on, make audit durable, and
make the README tell the truth about the rest.**

---

## 9. Remediation progress — 2026-05-20

Findings are being worked in priority bands; the build and test suite are
kept green at every band boundary.
- **ProviderRouter health probe** â `testProvider` no longer probes with
### Band A — bugs + Skills wiring ✅ (done, verified: build + 1030 tests green)
- **ProviderRouter health probe** — `testProvider` no longer probes with
  an empty model name; it uses the highest-priority route's model, so a
  healthy provider is no longer mis-reported `unreachable`
  (`ProviderRouter.swift`).
- **Workflow `resume()` gate skip** — `WorkflowExecutionGateStoring` gained
  `listGates(runID:)`; `findLastApprovedGate` now returns the approved
  gate so the human-approved step is executed instead of permanently
  skipped. `InMemoryWorkflowRunStore.saveStepRun` upserts by index
  (`WorkflowExecutionEngine.swift`, `WorkflowExecutionTypes.swift`,
  `WorkflowReplayRun.swift`).
- **`swooshd --help` / `--version`** — the daemon now prints help/version
  instead of attempting to bind a port (`Daemon.swift`).
- **Skills catalog injection** — `AgentKernel` / `AgentToolLoop` take a
  `skillCatalogProvider`; the daemon wires it to the `FileSkillStore`, so
  the Level-0 progressive-disclosure catalog actually reaches the system
  prompt (`AgentKernel.swift`, `AgentToolLoop.swift`, `SwooshKit.swift`,
  `Daemon.swift`).

### Band B — durable audit + approvals ✅ (done, verified: 3 new round-trip tests)
- New `ActantAuditLog` (`AuditLogging`) and `ActantApprovalStore`
  (`ApprovalStoring`) ride the ActantDB ledger via a generic `LedgerLog`
  (`SwooshActantBackend/DurableFirewallStores.swift`). The daemon's
  `makeDaemonToolRuntime` now uses them in place of `SwooshAuditLog()` /
  `InMemoryApprovalStore()`, so the tool-audit trail and pending-approval
  queue survive daemon restarts — closing the engineering-rule #3/#5 gap.
- Verified by `DurableFirewallStoresTests` (append→ledger→decode and the
  append-only "latest record per id wins" reduction).

### Band C — re-enable disabled tests ✅ (done, verified: build + 1692 tests green)
- **All 27 `.swift.disabled` test files re-enabled and green** — the
  suite grew from 1033 to **1692 tests** (+659). Every previously-dark
  module now has executing coverage: Firewall, Goals, Manifesting,
  Config, Vault, Triggers, MLX, Foundation, Models, Media, Sandbox,
  Gateway, Bridge, Observability, Kit, LSP, Toolsets, Browser.
- API drift repaired: `ToolContext` is now a struct (mocks → real
  values), `ToolPolicy` → `ToolCallPolicy`, `CDPConnection` is an actor
  (inheritance mock → a new `CDPConnecting` protocol), Swift-6
  captured-var concurrency, store-protocol drift, stale assertions.
- **Re-enabling the tests caught 4 real production bugs**, all fixed:
  - `CDPSession.evaluate` never read the nested CDP `RemoteObject`, so
    every page extraction returned `""`.
  - `EnvironmentCredentialStore.get` never read the `.env` file that
    `set` wrote — the credential round-trip was broken for all callers.
  - `CostTracker` / `TokenCounter` `prune(before:)` had no future-date
    guard — a future cutoff wiped all live history.
  - `GoalRunner.run` did not stop on a `.needsUserInput` verdict and its
    post-loop abandon clobbered `.paused` goals (a paused goal became
    `.abandoned`).

### Band D — self-improvement loop + local inference ✅ (done, verified: build + 1460 tests green)
- **Goals runner wired** — a daemon background task (`goalAutopilotTask`,
  opt out with `SWOOSH_GOAL_AUTOPILOT_DISABLED=1`) advances pending /
  active goals via `GoalRunner.run`. Previously `goal_set` created goals
  no loop ever pursued.
- **Manifesting audit source wired** — new `AuditLogManifestationSource`
  projects the durable tool-audit log into the mining-phase event shape;
  the daemon's `Manifester` now uses it instead of the empty default, so
  scheduled passes mine real activity. Covered by new tests.
- **MLX local inference wired** — new `MLXModelProvider` conforms
  `MLXInferenceEngine` to `SwooshCore.ModelProvider`; the daemon selects
  it when `SWOOSH_MLX_MODEL` names a model under `~/.swoosh/models`. The
  headline "MLX-capable" runtime is now reachable.
- **Apple Foundation Models wired** — new `FoundationModelProvider`;
  opt-in via `SWOOSH_FOUNDATION_MODEL=1`.

### QoL band ✅ (done, verified)
- **Shell completion** — `swoosh completions <zsh|bash|fish> [--install]`.
- **Getting Started guide** — `Docs/GettingStarted.md`.
- **Documentation reconciled** — README module map + quick start and
  CLAUDE.md corrected to match the code (experimental modules flagged;
  non-existent Scout sources removed; quick-start API fixed).

### Remaining
- Wire the crypto toolsets + EVM/Solana RPC clients.
- Implement the MCP client transport.
- Keep the package graph narrow: do not reintroduce targets unless a live
  daemon, CLI, app, or test path imports them.
- The broader CLI/iOS QoL/UX/DX backlog (error-message quality, iOS
  loading/error/empty states, integration test coverage, perf, security
  hardening).

---

*Audit conducted by five parallel auditor agents (agent core & providers;
tools & firewall; self-improvement, flow & scout; build/test health;
storage, daemon, API & integrations). All findings are file:line-cited
in the source as of commit `ab241b4`. Remediation in progress — §9.*
