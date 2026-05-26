# Claude Code Entrypoint

Apply `AGENTS.md` first. Then apply relevant modules from `rules/`.

Claude-specific assets:

- Hooks: `.claude/settings.json` and `.claude/hooks/`
- Slash commands: `.claude/commands/`
- General command docs: `commands/`

Before writing code, inspect the Xcode project and summarize targets, deployment targets, entitlements, privacy manifest, app extensions, and tests.

Use hooks as deterministic guardrails; do not rely only on prompt instructions.
