# AGENTS.md — Apple Agentic Swift 2026

You are coding in a Swift/Xcode repository for Apple platforms.

## Operating contract

1. **Inspect before editing.** Read package/project files, targets, entitlements, privacy manifest, deployment targets, tests, build settings, and existing architecture before changes.
2. **Make small compiling changes.** Preserve style, target membership, access control, localization, and architecture unless explicitly asked to refactor.
3. **Use Apple-native APIs first.** Prefer Swift, SwiftUI, Observation, SwiftData/Core Data, App Intents, Foundation Models, WidgetKit, ActivityKit, Core Spotlight, URLSession/Network, Keychain, StoreKit, BackgroundTasks, and Xcode tooling.
4. **Local-first agentic features.** Prefer on-device Foundation Models. Do not add hidden cloud AI, analytics, remote logging, prompt storage, or third-party SDKs.
5. **Type all agent boundaries.** Tool inputs, tool outputs, App Intent parameters, model outputs, persistence entities, network DTOs, and eval fixtures must be strongly typed.
6. **Treat tools as privileged.** Every agent tool needs a narrow scope, typed schema, explicit permissions, timeout, cancellation, error mapping, and tests.
7. **Expose core actions through App Intents.** Stable repeatable actions should work in Siri, Spotlight, Shortcuts, widgets, controls, and Apple Intelligence surfaces when appropriate.
8. **Use Fruta as a multiplatform reference.** Shared domain/services/views; thin platform scenes; target-specific App Clip/widget/intent adaptations; App Groups where required.
9. **Swift concurrency safety is mandatory.** Use Swift 6-ready patterns, strict concurrency, actors, `Sendable`, `@MainActor` for UI, and structured cancellation.
10. **Tests and automations are part of the feature.** Add/update Swift Testing, XCTest, UI automation, prompt/tool evals, and CI hooks.
11. **Privacy/App Review must stay aligned.** Update `PrivacyInfo.xcprivacy`, permission strings, App Privacy notes, AI disclosure, and review notes when data flows change.
12. **Accessibility/localization ship with the feature.** Add VoiceOver labels, Dynamic Type, keyboard support, localized strings, locale-aware formatting, and previews.

## Required discovery summary before implementation

- Targets and platforms.
- Deployment targets and Swift language mode.
- Existing UI/state architecture.
- Persistence and sync model.
- Entitlements, app groups, permissions, and privacy manifest status.
- Existing App Intents/widgets/App Clip/Live Activity/Spotlight integrations.
- Build/test commands available.
- Privacy/App Review implications.

## Forbidden unless explicitly approved

- Hidden server-side LLM calls or telemetry.
- Secrets in source, prompts, plists, env files, test logs, or generated code.
- Broad ATS/TLS exceptions.
- Destructive actions without explicit user confirmation.
- Autonomous purchases, messages, emails, posts, payments, or uploads.
- Unbounded transcript persistence.
- `Task.detached` as a quick fix for actor isolation.
- App-extension-unsafe APIs in extensions.

## Done means

- Code compiles on intended targets or exact unresolved SDK/build issue is documented.
- Tests or evals are added/updated.
- Privacy/App Review impact is stated.
- Accessibility/localization impact is stated.
- Build/test command is provided.
