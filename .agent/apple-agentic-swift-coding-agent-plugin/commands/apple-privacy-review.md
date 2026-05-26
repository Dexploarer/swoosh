# /apple-privacy-review

Audit privacy and App Review readiness.

Check:

- `PrivacyInfo.xcprivacy` exists and matches data flows.
- Required-reason API usage.
- Permission strings.
- App Privacy labels implications.
- AI/model behavior: local vs cloud, data retention, transcript logging, deletion controls.
- App Groups/shared containers.
- Network hosts and ATS exceptions.
- Sensitive frameworks: HealthKit, Photos, Contacts, Location, Speech, Microphone, Camera.
- App Review notes required.

Return concrete file changes and unresolved risks.
