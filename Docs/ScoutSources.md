# Swoosh Scout Sources

## Baseline Sources

| Source | Permission | Collects | Never collects | Example memories |
|--------|------------|----------|----------------|-----------------|
| DeviceScanner | none | OS, CPU, memory, arch | — | "Apple M4, 16 GB" |
| InstalledAppsScanner | none | /Applications list | app data | "Developer: has Xcode, Docker" |
| RunningAppsScanner | none | NSWorkspace apps | window contents | "Currently using Xcode, Arc" |
| SelectedFolderScanner | user-selected | dir structure, READMEs | file contents | "Active projects: Swoosh, ml-exp" |
| SwiftProjectScanner | user-selected | Package.swift, targets | source code | "Swoosh: 17 targets, MLX dep" |
| GitReposScanner | user-selected | remotes, branch names | credentials, diffs | "Uses GitHub, 12 active repos" |
| ShellEnvironmentScanner | none | PATH tools, shell type | env var values | "Has git, swift, docker, brew" |

## Permissioned Sources

| Source | Permission | Collects | Never collects |
|--------|------------|----------|----------------|
| CalendarScanner | EventKit | event patterns, free/busy | private event details |
| SafariTabsScanner | AppleScript/Automation | tab titles, URLs | cookies, form data |
| BrowserBookmarksScanner | extension | bookmark titles, URLs | passwords |

## Additional Sources

| Source | Permission | Collects | Never collects |
|--------|------------|----------|----------------|
| RemindersScanner | EventKit | reminder titles, lists | — |
| ContactsScanner | Contacts | names, orgs, relationships | phone, email, address |
| NotesScanner | AppleScript | note titles, summaries | full content by default |

## Redaction rules

All records pass through SecretRedactor before storage:

1. API keys (`sk-*`, `ghp_*`, `xoxb-*`) → `[REDACTED_API_KEY]`
2. Bearer tokens → `Bearer [REDACTED]`
3. SSH private keys → `[REDACTED_PRIVATE_KEY]`
4. Long hex tokens (64+ chars) → `[REDACTED_HEX_TOKEN]`
5. `.env` style `password=*` → `password=[REDACTED]`
6. Cookie/session values → `[REDACTED_COOKIE]`

## Pipeline

```
ScoutSource.scan()
  → [ScoutRecord]
  → SecretRedactor.redact()
  → [RedactedScoutRecord]
  → CandidateGenerator.generate()
  → [MemoryCandidate]
  → UserReviewQueue
  → approve/reject/edit
  → [ApprovedMemory] → SQLite vault
  → AuditLog.append()
```
