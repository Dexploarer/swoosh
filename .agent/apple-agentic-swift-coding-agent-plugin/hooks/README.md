# Hooks

Hooks are deterministic guardrails for agent actions. They complement rules.

## Included hook families

- `.claude/hooks/` — Claude Code-style shell hooks registered in `.claude/settings.json`.
- `.agent/hooks/` — agent-agnostic hooks that can be wired into other tools.
- `scripts/` — reusable validation scripts used by hooks and CI.

## Design

- Pre hooks block unsafe actions before they happen.
- Post hooks summarize and validate after edits/commands.
- Slow checks belong in CI; fast checks belong in hooks.
- Hooks must never print secrets.
