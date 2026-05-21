# .claude/ — project-local Claude Code config

This directory tailors how Claude Code works on the Swoosh repo. It layers on top of `~/.claude/` (user-level config + skills).

## Layout

```
.claude/
├── README.md              # this file
├── settings.json          # permission allowlist + dangerous-pattern denies
├── commands/              # custom slash commands
│   └── check.md           # /check — quick build + targeted test
└── skills/                # on-demand procedural skills (load by name)
    ├── add-swoosh-tool/       # multi-file checklist for new SwooshTools
    ├── coderabbit-batch-fix/  # batch review-comment application
    ├── daemon-up/             # start swooshd + verify iPhone pairing
    ├── mcp-stdio-debug/       # cooperative-pool deadlock triage
    ├── replay-workflow/       # SwooshFlow replay procedure
    ├── run-swoosh-tests/      # test filter patterns + multi-filter hang fix
    ├── swoosh-safety-gates/   # the 8 engineering rules as a checklist
    └── xcodegen-roundtrip/    # when to regenerate, sim vs device builds
```

Plus nested `CLAUDE.md` files at:
- `Sources/SwooshFirewall/CLAUDE.md`
- `Sources/SwooshFlow/CLAUDE.md`
- `Sources/SwooshScout/CLAUDE.md`
- `Apps/SwooshiOS/CLAUDE.md`

These auto-load when Claude edits files in those subtrees, layering above the repo-root `CLAUDE.md`.

## What goes where

- **Root `CLAUDE.md`** — architecture map, build commands, the 8 engineering rules, conventions. Always loaded.
- **Subdir `CLAUDE.md`** — invariants that only matter when editing that subtree (firewall has no bypass paths; ActantBackend stays <100 LoC; iOS imports only SwooshClient; etc.).
- **`.claude/skills/`** — multi-step procedures Claude pulls in by name (the model finds them via their `description:` line and the trigger phrases there).
- **`.claude/commands/`** — slash commands the user invokes directly (`/check`).
- **`.claude/settings.json`** — pre-approve safe Bash patterns, deny dangerous ones.

## Distinction from `Skills/Bundled/`

`Skills/Bundled/` at the repo root holds **Swoosh's own runtime skills** — the agent (Swoosh) consumes them at run time via `BundledSkillLoader`. They have a different frontmatter shape (`trust:`, `triggers:`, `category:`, `platforms:`).

`.claude/skills/` are **Claude Code's skills** — they affect how Claude (the model) operates on this codebase. Different layer, different audience. Don't conflate them.

## Maintenance

- If a skill is wrong or stale, edit it. The trigger phrases in `description:` are how the model finds the skill — if it isn't getting picked up, the description is too generic.
- If a CLAUDE.md balloons over ~50 lines, extract a skill instead. Subdir CLAUDE.md should stay tight.
- If `settings.json` blocks a common workflow with permission prompts, add the pattern to `allow`. If it lets through something risky, add to `deny`.
