# SwooshScout

The personalization scanner. Loaded automatically when Claude edits here.

## Pipeline order (don't reorder)

1. **Source scan** — `ScoutSource.scan(...)` produces raw records.
2. **Secret redactor** — runs **immediately** on raw records. Keys, tokens, PII, browser cookies stripped before anything else sees them.
3. **ActantDB save** — `saveScoutRecord` persists redacted records (raw records never persist).
4. **Candidate generator** — turns records into memory candidates.
5. **MemoryStore.propose** — candidate lands in the user's review inbox.
6. **MemoryStore.approve / reject** — explicit user action.
7. **Prompt injection** — only `.approved` memories enter prompts. Engineering rule #6.

Rejected candidates are **purged**, never silently retained — purging is the safety contract.

## Sensitivity gating

Every personal source has a `Sensitivity` (`.low`/`.medium`/`.high`). `PersonalizationDepth` profiles gate which sensitivity tier is even scanned. `.high` sources (calendar cadence, app usage, focus mode, recent docs, sleep) require `PersonalizationDepth.deep`. Don't lower a source's sensitivity to make it run on default depth — bump the user's profile if you want more.

## Aggregate-only sources

`CalendarSource` and `RemindersSource` emit **cadence patterns and backlog counts only** — never titles, attendees, or reminder text. This is non-negotiable; the data shape must remain aggregate. Adding a "but just for one source, with a redacted title" path is exactly the slippery slope that breaks user trust.

## Permission flow per source

`ScoutSource.checkPermission` returns `SourcePermissionStatus`: one of `.granted | .denied | .notDetermined | .restricted`. `.notDetermined` means the user has never been asked; `.restricted` means the OS denies regardless of consent (parental controls, MDM, missing entitlement, unsupported platform). Only `.granted` lets a source's `scan(...)` run.

The autopilot in `swooshd` uses `ScoutPermissionMode.skipUnavailable` so passive personalization never opens OS permission prompts while unattended. The default value of `ScoutPipelineOptions.permissionMode` is also `.skipUnavailable` (changed in 0.9S) — foreground callers that genuinely want to prompt the user must pass `.requestIfNeeded` explicitly. Don't flip the autopilot mode to `.requestIfNeeded` — that breaks the unattended invariant.
