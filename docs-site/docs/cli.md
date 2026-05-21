---
id: cli
title: CLI Reference
sidebar_position: 3
---

# CLI Reference

The `swoosh` CLI is the primary developer interface. Default subcommand is `chat`.

## Subcommands

### Setup

```bash
swoosh setup quick
swoosh setup quick --permissions <safe|developer|automation|power|autonomous|custom>
```

Full onboarding flow: profiles your machine, creates `~/.swoosh/`, and writes runtime config. Idempotent.

---

### Chat / Ask

```bash
swoosh chat              # interactive REPL
swoosh ask "<question>"  # one-shot answer
```

The interactive REPL is the default when you run `swoosh` with no subcommand.

---

### Doctor

```bash
swoosh doctor            # system diagnostics (~16 checks)
swoosh doctor --fix      # auto-repair what it can
swoosh doctor --json     # machine-readable output
```

Checks: installation, daemon, config, secrets, model, storage, privacy.

---

### Scout

```bash
swoosh scout run         # run environment scan
swoosh scout report      # show last scan report
```

Scans your Mac for dev environment facts, installed apps, Git repos, shell tools, and more. Results are proposed as memory candidates for your review.

---

### Memory

```bash
swoosh memory list       # list memory candidates (pending + approved)
swoosh memory approve    # approve pending candidates interactively
swoosh memory show       # show approved memories
```

---

### Provider

```bash
swoosh provider auth     # interactive: pick a provider, paste a key
```

Stores keys in the macOS Keychain (`ai.swoosh.agent`), never in plaintext.

---

### Model

```bash
swoosh model             # show current model routing
```

---

### Daemon

```bash
swoosh daemon status     # check swooshd health
```

---

### Skills

```bash
swoosh skills list       # list installed/promptable skills
swoosh skills install    # install an agentskills-style skill
```

---

### Cron

```bash
swoosh cron list         # list scheduled jobs
swoosh cron create       # create a scheduled agent job
```

---

### Terminal

```bash
swoosh terminal backends   # list terminal execution backends
```

---

### Chat adapters

```bash
swoosh chat-adapters       # list and toggle platform/state adapters
```

---

### Permissions

```bash
swoosh permissions --status  # print active profile, tool policy, safety flags
```

---

### Completions

```bash
swoosh completions zsh --install
swoosh completions bash --install
swoosh completions fish --install
swoosh completions <shell>     # print script (no install)
```

---

## Shell slash commands

Available inside the interactive REPL (`swoosh chat`):

| Command | Category | Description |
|---------|----------|-------------|
| `/help`, `/h`, `/?` | General | List all commands |
| `/exit`, `/q`, `/quit` | General | Exit shell |
| `/clear` | General | Clear screen |
| `/status`, `/s` | General | Show session status |
| `/model`, `/m` | Agent | Show/change model |
| `/tools`, `/t` | Agent | List available tools |
| `/sessions` | Agent | Manage chat sessions |
| `/why` | Agent | Explain context used in last response |
| `/repeat`, `/r` | Agent | Turn last task into a workflow draft |
| `/scout` | Personalization | Run environment scan |
| `/vault`, `/v`, `/memory` | Personalization | Manage memory candidates |
| `/permissions`, `/p`, `/perms` | System | Show permission profile |
| `/firewall`, `/fw` | System | Show firewall rules |
| `/local` | Development | Local model / MLX status |
| `/db` | Development | ActantDB ledger status (event count, last event ID) |

## Environment variables

| Variable | Effect |
|----------|--------|
| `SWOOSH_HOST` | Daemon bind address (default `127.0.0.1`; set `0.0.0.0` for LAN) |
| `SWOOSH_API_TOKEN` | Override bearer token |
| `SWOOSH_ACTANTDB_PATH` | Path to `actantdb` binary |
| `SWOOSH_MLX_MODEL` | Select a local MLX model |
| `SWOOSH_FOUNDATION_MODEL` | Select Apple Foundation Models adapter |
| `ACTANT_BASE_URL` | ActantDB server URL (auto-set by daemon) |
