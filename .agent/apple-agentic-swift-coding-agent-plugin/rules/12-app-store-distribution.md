# 12 — App Store, TestFlight, and Distribution

## App Review checklist

- Privacy manifest present and accurate.
- App Privacy labels match code and server behavior.
- Permission strings are specific.
- AI behavior disclosed when it processes user data or generates content.
- User-generated content moderation/reporting where required.
- Purchases/subscriptions use StoreKit and clear terms.
- Sign in with Apple used where required by account flows.
- App Clip metadata and invocation flows tested.
- Review notes include test accounts, feature flags, AI behavior, model location, and edge cases.

## TestFlight readiness

- Archive succeeds.
- No debug entitlements/secrets.
- Crash-free smoke test.
- Background modes justified.
- Extension targets launch.
- Widgets/App Clip/Shortcuts tested.
