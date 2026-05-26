# Apple Agentic Swift 2026 Coding-Agent Plugin

A portable **coding-agent plugin / rules pack** for building agentic apps with Swift across Apple products.

It includes:

- **Rules** for Swift, SwiftUI, Foundation Models, App Intents, privacy, testing, accessibility, App Review, and Fruta-style multiplatform architecture.
- **Hooks** for deterministic guardrails before/after agent tool use.
- **Slash commands** for repeatable workflows such as `/apple-plan`, `/apple-agent-tool`, `/apple-fruta-architect`, `/apple-privacy-review`, and `/apple-release`.
- **Automations** for CI, project audits, privacy checks, prompt/tool evals, and Xcode build/test validation.
- **Templates** for App Intents, agent orchestration, Keychain, networking, SwiftData patterns, privacy manifests, widgets, and App Clips.

## Install

Copy this folder into a Swift/Xcode repo root. Then use the entrypoint your agent understands.

| Agent / IDE | Entry file |
|---|---|
| Generic coding agent | `AGENTS.md` |
| Claude Code | `CLAUDE.md`, `.claude/settings.json`, `.claude/commands/` |
| Cursor | `.cursor/rules/apple-agentic-swift-2026.mdc` |
| GitHub Copilot | `.github/copilot-instructions.md` |
| Codex-style agents | `.codex/AGENTS.md` |
| Windsurf | `.windsurfrules` |

## First prompt to run

```text
Read AGENTS.md, rules/, hooks/README.md, commands/README.md, and docs/research-brief-2026.md. Inspect the Xcode project, targets, entitlements, privacy manifest, deployment targets, tests, and build settings. Produce a brief plan before editing. Use the Fruta sample as a reference for shared SwiftUI architecture, widgets, App Clip target separation, App Groups, localization, Sign in with Apple, Apple Pay/PassKit, and StoreKit configuration patterns.
```

## Design stance

- Native Apple stack first.
- Local-first AI by default.
- Foundation Models for bounded on-device generation, guided generation, and tool calling.
- App Intents for discoverable system actions through Siri, Spotlight, Shortcuts, widgets, controls, Action button, and Apple Intelligence surfaces.
- Swift 6.x data-race safety, actor isolation, and structured concurrency.
- Privacy/App Review readiness as a build gate.
- Fruta-inspired shared-domain architecture for multiplatform app + widget + App Clip targets.

## Included slash commands

Claude Code-style slash commands are under `.claude/commands/`; agent-agnostic copies are under `commands/`.

- `/apple-plan` — inspect and plan an Apple-platform task.
- `/apple-agent-tool` — implement a bounded Foundation Models/App Intents-compatible tool.
- `/apple-app-intent` — expose a feature through App Intents/App Shortcuts/AppEntity.
- `/apple-fruta-architect` — refactor toward a Fruta-like shared codebase with widgets/App Clip compatibility.
- `/apple-privacy-review` — audit privacy manifests, data flows, permissions, AI disclosure, and App Review notes.
- `/apple-test` — create/run Swift Testing, XCTest, UI automation, prompt/tool evals.
- `/apple-build-fix` — diagnose Xcode/SwiftPM build failures.
- `/apple-release` — prepare TestFlight/App Store readiness checks.

## Included hooks

- Pre-tool guard: blocks dangerous shell commands and sensitive file edits.
- Xcode target guard: warns when generated Swift files may not be in target membership.
- Post-edit validator: runs lightweight Swift/project/privacy checks after edits.
- Post-bash summarizer: extracts build/test failures from noisy output.
- Stop hook: prints a deterministic completion checklist.

Hooks are code-enforced guardrails; rules are model context. Use both.
