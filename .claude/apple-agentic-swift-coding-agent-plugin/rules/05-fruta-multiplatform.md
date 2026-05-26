# 05 — Fruta-Style Multiplatform Architecture

Use the Fruta sample as a reference for a feature-rich SwiftUI app with shared code and target-specific surfaces.

## Pattern

```text
Shared domain/services/views/resources
  ├─ iOS/iPadOS app
  ├─ macOS app
  ├─ Widget extension
  ├─ App Clip
  ├─ App Intents extension when needed
  └─ Tests/previews/sample data
```

## Practices

- Put models, repositories, use cases, and reusable SwiftUI views in shared code.
- Keep app/widget/App Clip/intent targets thin.
- Use App Groups only where extension-safe shared storage is required.
- Avoid duplicating business logic for App Clip.
- Use compile-time feature flags only at target boundaries.
- Keep App Clip flow single-purpose and lightweight.
- Use localization from the start.
- Keep payments/account flows system-native: Sign in with Apple, Apple Pay/PassKit, StoreKit where appropriate.
