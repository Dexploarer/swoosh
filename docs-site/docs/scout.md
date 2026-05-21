---
id: scout
title: Scout & Memory
sidebar_position: 6
---

# Scout & Memory

Scout is Swoosh's personalization scanner. It profiles your Mac environment, generates memory candidates, and routes them through a human-in-the-loop approval queue before any of the data reaches the agent prompt.

## What Scout collects

### Baseline sources (no permissions required)

| Source | Collects | Never collects |
|--------|----------|----------------|
| `DeviceScanner` | OS, CPU, memory, architecture | — |
| `InstalledAppsScanner` | `/Applications` list | App data or contents |
| `RunningAppsScanner` | NSWorkspace app list | Window contents |
| `SelectedFolderScanner` | Directory structure, READMEs | File contents |
| `SwiftProjectScanner` | `Package.swift`, targets | Source code |
| `GitReposScanner` | Remotes, branch names | Credentials, diffs |
| `ShellEnvironmentScanner` | PATH tools, shell type | Env var values |

### Permissioned sources

| Source | Permission | Collects | Never collects |
|--------|------------|----------|----------------|
| `CalendarScanner` | EventKit | Event patterns, free/busy | Private event details |
| `SafariTabsScanner` | AppleScript/Automation | Tab titles, URLs | Cookies, form data |
| `BrowserBookmarksScanner` | Extension | Bookmark titles, URLs | Passwords |
| `RemindersScanner` | EventKit | Reminder titles, lists | — |
| `ContactsScanner` | Contacts | Names, orgs, relationships | Phone, email, address |
| `NotesScanner` | AppleScript | Note titles, summaries | Full content by default |

### Deep personalization sources (daemon-side, `Sensitivity.high`)

These only run at `PersonalizationDepth.deep` and require explicit permission grants:

| Source | Permission | What it measures |
|--------|------------|-----------------|
| `AppUsageSource` | `appUsageRead` | Per-app focus time (aggregated totals, never window titles) |
| `CalendarSource` | `calendarRead` | Cadence patterns and backlog counts — never titles or attendees |
| `RemindersSource` | `remindersRead` | Backlog counts — never reminder text |
| `FocusModeSource` | `focusModeRead` | Active Focus mode |
| `RecentDocumentsSource` | `recentDocumentsRead` | macOS shared-file-list aggregates |
| `HealthSleepSource` | `healthSleepRead` | iOS HealthKit (entitlement-gated) |
| `MusicHistorySource` | `musicLibraryRead` | MusicKit (entitlement-gated) |
| `ScreenTimeSource` | `screenTimeRead` | iOS FamilyControls / DeviceActivity (entitlement-gated) |

## Secret redaction

All records pass through `SecretRedactor` **before storage**. Redaction rules:

| Pattern | Replacement |
|---------|-------------|
| API keys (`sk-*`, `ghp_*`, `xoxb-*`) | `[REDACTED_API_KEY]` |
| Bearer tokens | `Bearer [REDACTED]` |
| SSH private keys | `[REDACTED_PRIVATE_KEY]` |
| Long hex tokens (64+ chars) | `[REDACTED_HEX_TOKEN]` |
| `.env`-style `password=*` | `password=[REDACTED]` |
| Cookie / session values | `[REDACTED_COOKIE]` |

## Pipeline

```
ScoutSource.scan()
  → [ScoutRecord]
  → SecretRedactor.redact()
  → [RedactedScoutRecord]
  → CandidateGenerator.generate()
  → [MemoryCandidate]
  → CandidateReviewPlanner.dedupe()   ← against pending + approved memories
  → UserReviewQueue
  → approve / reject / edit
  → [ApprovedMemory] → ActantDB memory store
  → AuditLog.append()
```

## Privacy boundary — what never reaches the model

`SwooshCore/PromptBuilder` is the enforced privacy boundary. Only **approved memories** and a setup-report summary enter agent prompts. The following **never** enter prompts:

- Rejected memory candidates
- Raw Scout records
- Browser cookies or session tokens
- Private SSH keys or API keys
- Full calendar event titles or attendee lists
- Raw health or screen-time data

## Running Scout

```bash
# Full scan
swift run swoosh scout run

# Review candidates
swift run swoosh memory list
swift run swoosh memory approve

# Daemon autopilot (passive — no OS prompts)
# Runs automatically when swooshd is running
```

In the REPL:

```
/scout     # trigger scan
/vault     # review candidates
```

## Autopilot

`swooshd` runs Scout autopilot continuously with `ScoutPermissionMode.skipUnavailable`. This means:

- It reads passive, already-granted sources (device info, running apps, app-usage logs).
- It **never** raises OS permission dialogs while unattended.
- It deduplicates against existing pending/approved memories before proposing new candidates.
