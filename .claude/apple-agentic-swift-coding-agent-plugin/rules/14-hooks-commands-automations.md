# 14 — Hooks, Slash Commands, and Automations

Use prompt rules for judgment; use hooks and automations for deterministic enforcement.

## Hooks

- PreToolUse: block dangerous shell commands and sensitive file writes.
- PostToolUse: run fast format/lint/project checks after edits.
- Stop: print deterministic completion checklist.
- Notification: optional desktop notification when agent needs input.

## Slash commands

Use `/apple-plan` before large work, `/apple-privacy-review` before release or when data flows change, `/apple-test` after implementation, and `/apple-release` before TestFlight/App Store.

## Automations

- Run `scripts/apple-agent-doctor.sh` at session start or before major edits.
- Run `scripts/validate-agentic-apple.sh` before committing.
- Run GitHub Actions workflow in `.github/workflows/apple-agentic-ci.yml` on pull requests.
- Keep automations fast enough for agent iteration; move slow simulator matrices to CI.
