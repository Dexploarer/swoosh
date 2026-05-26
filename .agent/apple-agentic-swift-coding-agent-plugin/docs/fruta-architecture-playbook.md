# Fruta Architecture Playbook

## Target structure

```text
AppName/
  Shared/
    Domain/
    Services/
    Agent/
    Persistence/
    Views/
    Resources/
  App-iOS/
  App-macOS/
  WidgetExtension/
  AppClip/
  IntentsExtension/
  Tests/
  UITests/
```

## Rules

- Shared domain code cannot import extension-unsafe UI/application APIs.
- App Clip uses the same services with reduced capability flags.
- Widget reads only extension-safe state.
- App Intents call domain services, not SwiftUI views.
- Agent tools call domain services through a policy layer.
- App Groups are explicit and audited.
- StoreKit config files are committed for local testing but never contain secrets.

## Refactor path

1. Identify duplicated code between app/widget/App Clip.
2. Extract shared model/service protocols.
3. Move UI-independent logic to `Shared`.
4. Add target-specific adapters.
5. Add tests around extracted services.
6. Verify App Clip/widget extension-safety.
7. Re-run privacy and entitlement audits.
