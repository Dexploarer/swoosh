# Codex Workspace Setup

This directory holds repo-local Codex configuration and hooks.

- `config.toml` keeps Swoosh on the local trusted-project execution profile.
- `hooks.json` wires prompt memory capture and Swoosh-specific command guardrails.
- `scripts/pre-tool-use.sh` emits context before risky or architecture-sensitive shell commands.

The hook layer is advisory. Git enforcement lives in `.githooks/`.
