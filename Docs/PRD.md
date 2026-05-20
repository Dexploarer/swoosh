# Swoosh — Product Requirements Document

## Target user

Swift/Mac developers who want a local-first, permissioned agent that understands their environment.

## Product Promise

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

## Product Surface

Swoosh ships the setup-to-first-use spine and keeps adjacent capabilities visible when they have concrete runtime state. Messaging adapters, skills, cron jobs, terminal backends, MCP, workflows, Scout, and iOS chat should expose toggleable or configured status instead of hidden scaffolding or empty placeholder success.

## Success criteria

- [ ] Swoosh CLI `setup quick` completes end-to-end
- [ ] Scout scans installed apps, Swift projects, Git repos, shell env
- [ ] Scout autopilot proposes new candidates from passive daemon signals without prompting for permissions
- [ ] Secret redactor strips API keys, tokens, SSH keys from records
- [ ] Memory candidates generated and presented for review
- [ ] User can approve/reject/edit memory candidates via CLI
- [ ] Approved memories stored in ActantDB through `ActantAgent.MemoryStore`
- [ ] Setup report generated and saved
- [ ] `swoosh doctor` reports system health
- [ ] Audit log records all scan/memory/permission actions
- [ ] First personalized agent task runs using approved memories
- [ ] `swooshd` serves bearer-gated chat to the iOS client over LAN
- [ ] Skills can be installed, reviewed, searched, and loaded with support files
- [ ] Cron jobs can be created, paused, resumed, run, and audited
- [ ] Terminal backend options can be listed and configured
- [ ] Chat SDK platform and state adapters can be toggled on or off
