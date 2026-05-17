# Swoosh v0 — Product Requirements Document

## Target user

Swift/Mac developers who want a local-first, permissioned agent that understands their environment.

## v0 promise

> Swoosh is a permissioned, local-first Mac agent that learns your environment during setup and turns that into useful memory and workflows.

## Setup flow

```
Install Swoosh
→ choose personalization depth (minimal / recommended / deep)
→ grant selected permissions
→ scan apps / files / calendar / dev environment
→ generate memory candidates
→ user approves / rejects / edits memories
→ produce personal setup report
→ run first useful personalized task
→ offer "Make this repeatable"
```

## First task

"Understand my Mac/dev setup and make a personalized operating plan."

Output: profile, tools, workflows, model routing, memory settings, first 5 automations.

## Non-goals for v0

- Full messaging gateway (Telegram, Discord, Slack)
- MCP server hosting
- Browser automation / CDP
- Voice / TTS / STT
- Multi-agent delegation
- Team sync / hosted backend
- Plugin system
- Media processing

## Success criteria

- [ ] Swoosh CLI `setup quick` completes end-to-end
- [ ] Scout scans installed apps, Swift projects, Git repos, shell env
- [ ] Secret redactor strips API keys, tokens, SSH keys from records
- [ ] Memory candidates generated and presented for review
- [ ] User can approve/reject/edit memory candidates via CLI
- [ ] Approved memories stored in SQLite vault
- [ ] Setup report generated and saved
- [ ] `swoosh doctor` reports system health
- [ ] Audit log records all scan/memory/permission actions
- [ ] First personalized agent task runs using approved memories
