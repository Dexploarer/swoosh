# 07 — Data, Persistence, and Agent Memory

Separate memory classes.

| Memory | Storage | Policy |
|---|---|---|
| Session transcript | In-memory model session | Bounded; compact; not persisted by default. |
| User content | SwiftData/Core Data/files/CloudKit | Product-owned; user-visible; deletable. |
| Search index | Core Spotlight/AppEntity metadata | Reconstructable; avoid sensitive over-indexing. |
| Secrets/tokens | Keychain | Never in source, UserDefaults, plists, prompts, or logs. |
| Preferences | UserDefaults/AppStorage | Low sensitivity only. |
| Eval data | Test fixtures | Synthetic or explicitly consented. |

## Persistence rules

- Prefer SwiftData for new local structured data where deployment targets support it.
- Use Core Data for mature existing stacks, advanced migration needs, or legacy support.
- Use CloudKit only when sync is a requirement and privacy/conflict behavior is designed.
- Do not store raw AI prompts/transcripts unless product requirements, consent, retention, and deletion flows are defined.
