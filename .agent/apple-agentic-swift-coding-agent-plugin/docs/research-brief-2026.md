# Research Brief — Agentic Swift Apps on Apple Platforms, 2026

## Core synthesis

A strong Apple-native agentic app is not just chat. It combines:

- **Foundation Models** for local guided generation and tool calling.
- **App Intents** to expose app capabilities and content to Siri, Spotlight, Shortcuts, widgets, controls, Action button, and Apple Intelligence.
- **SwiftUI** and Fruta-like shared architecture for app, widget, App Clip, and extensions.
- **Swift concurrency** for responsive, data-race-safe orchestration.
- **Privacy manifests and App Review artifacts** as release blockers.
- **Hooks, slash commands, and automations** so coding agents produce repeatable, safe changes.

## 2026 best-practice matrix

| Area | Best practice |
|---|---|
| Model route | Use on-device Foundation Models by default; cloud only with explicit product need and disclosure. |
| Output | Use guided generation/typed schemas for anything entering app state. |
| Tools | Narrow, typed, permission-aware, cancellable, time-bounded, tested. |
| App actions | Expose repeatable workflows via App Intents/App Shortcuts/AppEntity. |
| Architecture | Shared domain/services/views with thin app/widget/App Clip/intent targets, following Fruta’s pattern. |
| Persistence | SwiftData for new local structured data; Keychain for secrets; no transcript persistence by default. |
| Concurrency | Swift 6-ready strict concurrency, actor isolation, `Sendable`, cancellation. |
| Privacy | Data minimization, privacy manifest, App Privacy labels, specific permission copy, AI disclosure. |
| Tests | Swift Testing + XCTest + UI automation + prompt/tool evals. |
| Agent workflow | Rules for judgment, hooks for enforcement, slash commands for repeatability, CI automations for gatekeeping. |

## Fruta integration

Fruta should inform this plugin’s architecture in four ways:

1. Shared SwiftUI app structure across Apple platforms.
2. Widget and App Clip targets that reuse domain logic instead of duplicating it.
3. App Groups and extension-safe services where shared storage is necessary.
4. System-native account/payment/store flows such as Sign in with Apple, PassKit/Apple Pay, and StoreKit configuration.

## Agentic feature completion checklist

- Availability and fallback behavior defined.
- Developer instructions separated from user content.
- Typed model output validated.
- Tools are least-privilege and tested.
- App Intents added where system exposure matters.
- Privacy manifest/App Privacy notes updated.
- Accessibility and localization added.
- Build/test/eval automation passes.
