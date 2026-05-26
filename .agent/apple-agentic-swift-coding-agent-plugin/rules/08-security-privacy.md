# 08 — Security and Privacy

Security/privacy are feature requirements.

## Required checks

- Does this feature collect, process, store, transmit, or infer user data?
- Does it use AI over user content?
- Does it require permissions: location, photos, camera, microphone, contacts, calendar, health, speech, files?
- Does it add network hosts or third-party SDKs?
- Does it use required-reason APIs?
- Does it need a `PrivacyInfo.xcprivacy` change?
- Does App Store Connect privacy labeling need a change?

## Practices

- Use Keychain for secrets.
- Use ATS; avoid exceptions.
- Minimize data in prompts and tool outputs.
- Redact sensitive values from logs and test output.
- Keep permission copy specific and user-benefit oriented.
- Do not add analytics or remote logging silently.
