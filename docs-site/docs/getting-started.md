---
id: getting-started
title: Getting Started
sidebar_position: 2
---

# Getting Started

This guide takes you from a fresh clone to a working agent — chatting in the terminal, running the daemon, and pairing your iPhone.

## Prerequisites

- macOS 26 or later, Apple silicon.
- Swift 6.3+ (`swift --version`).
- Xcode 26+ (only needed for the menu-bar / iOS apps).
- Rust toolchain (`cargo --version`) — needed to build **ActantDB**, the durable-state backend.

## 1. Clone and build

```bash
git clone https://github.com/Dexploarer/swoosh.git && cd swoosh
swift build           # builds the library, CLI, and daemon
```

The first build resolves packages and compiles ~55 modules; expect a couple of minutes cold, seconds incrementally. Run from the repo with `swift run swoosh …`, or copy `.build/debug/swoosh` and `.build/debug/swooshd` onto your `PATH`.

:::note ActantDB
The daemon stores all durable state in **ActantDB**, an event-sourced sibling project. `swooshd` spawns the `actantdb` binary automatically. If it is not found, build it once:

```bash
cd ../actantDB && cargo build
```

Or set `SWOOSH_ACTANTDB_PATH=/path/to/actantdb` before starting the daemon.
:::

## 2. Guided setup

```bash
swift run swoosh setup quick
```

`setup quick` profiles your machine, creates `~/.swoosh/`, and writes a runtime config (permission profile, tool policy, safety flags). Re-run it any time; it is idempotent.

## 3. Configure a model provider

```bash
swift run swoosh provider auth   # interactive — pick a provider, paste a key
```

Keys are stored in the macOS Keychain (service `ai.swoosh.agent`), never in plaintext config.

**Supported providers:**

| Provider | Notes |
|----------|-------|
| OpenAI | API key via Keychain |
| OpenRouter | API key via Keychain |
| Ollama / LM Studio | Local OpenAI-compatible endpoint |
| Eliza Cloud | elizaOS hosted inference |
| Apple Foundation Models | On-device, free, via `SwooshFoundation` |
| MLX (Apple silicon) | Local via `SwooshMLX`, select with `SWOOSH_MLX_MODEL` |

With no key configured the agent still answers via a local diagnostic fallback — useful to confirm wiring, not a real model.

## 4. Health check

```bash
swift run swoosh doctor
```

Runs ~16 checks across installation, daemon, config, secrets, model, storage, and privacy. `swoosh doctor --fix` repairs what it can; `--json` emits machine-readable output.

## 5. Chat from the terminal

```bash
swift run swoosh chat             # interactive REPL (the default command)
swift run swoosh ask "Summarize the last commit"   # one-shot
```

### Shell banner

When you open the REPL, Swoosh shows its current state:

```
╔═══════════════════════════════════════════════╗
║                   Swoosh                      ║
║     Swift-native agent runtime for macOS      ║
╚═══════════════════════════════════════════════╝

  Model:        not configured (MLX-capable: 7B, 13B)
  Mode:         interactive
  Memory:       4 approved, 0 pending
  Permissions:  safe
  State plane:  ActantDB
  Session:      default

  Type /help for commands, or ask a question.
```

## 6. Run the daemon

```bash
swift run swooshd                 # foreground; Ctrl-C to stop
swooshd --help                    # options and environment variables
```

`swooshd` binds `127.0.0.1:8787` by default. On first start it mints a bearer token, prints it, and persists it to `~/.swoosh/api_token`. Every `/api/*` request requires that token.

To expose the daemon on your LAN (required for iPhone pairing):

```bash
SWOOSH_HOST=0.0.0.0 swift run swooshd
```

The bearer token is still required — the loopback default is defense in depth, not the only protection.

## 7. Pair your iPhone

1. Build and run **SwooshiOS** (`Apps/SwooshiOS`) on your device.
2. In the app, open the drawer → **Settings → Pairing**.
3. Enter the daemon host (`http://<your-mac>.local:8787`) and paste the token from `~/.swoosh/api_token`.
4. Tap **Pair**. Chat, Connections, and Settings now load live data.

## 8. Shell completion

```bash
swoosh completions zsh --install   # writes script + prints activation steps
swoosh completions bash --install
swoosh completions fish --install
```

`swoosh completions <shell>` (without `--install`) prints the script if you prefer to place it yourself.

## File layout

Everything lives under `~/.swoosh/`:

| Path | Contents |
|------|----------|
| `config.json` | Runtime configuration |
| `api_token` | Daemon bearer token (mode `0600`) |
| `actant.db` | ActantDB event ledger — sessions, memories, audit |
| `skills/`, `goals/`, `cron/` | Self-improvement state |
| `logs/` | Daemon + ActantDB logs |
| `artifacts/` | Generated media and files |
| `models/` | Downloaded MLX models |

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `FATAL: could not start ActantDB` | Build actantdb (`cd ../actantDB && cargo build`) or set `SWOOSH_ACTANTDB_PATH` |
| iPhone can't reach the daemon | Start with `SWOOSH_HOST=0.0.0.0`; confirm both devices are on the same Wi-Fi |
| Bearer token rejected | Re-copy `~/.swoosh/api_token` — it changes if the file is deleted |
| Agent replies seem generic | No provider key configured — run `swoosh provider auth` |
| Anything else | `swoosh doctor` first; it names the failing component and a fix command |
