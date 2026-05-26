# App Clip Bootstrap Pattern

- Share domain models and services with the full app.
- Keep App Clip-specific state minimal.
- Gate unsupported features behind compile-time flags or runtime capability checks.
- Use App Groups only when the App Clip/widget/full app need shared state.
- Promote full app using system UI when deeper account, history, sync, or purchase features are needed.

```swift
#if APPCLIP
let featureSet: FeatureSet = .appClip
#else
let featureSet: FeatureSet = .fullApp
#endif
```
