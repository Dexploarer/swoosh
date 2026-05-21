# Getting Started with Swoosh

This guide takes you from a fresh clone to a working agent — chatting in
the terminal, running the daemon, and pairing your iPhone.

## What you get

- **`swoosh`** — a developer CLI (chat, setup, diagnostics, memory, …).
- **`swooshd`** — a local daemon that hosts the agent kernel and serves a
  bearer-gated HTTP API.
- **Swoosh for iOS** — a thin client app that pairs with `swooshd`.

The Mac is the hub: it runs the kernel, tools, providers, and storage.
The iPhone is a thin client over HTTP.

## 1. Prerequisites

- macOS 26 or later, Apple silicon.
- Swift 6.3+ (`swift --version`).
- Xcode 26+ (only needed for the menu-bar / iOS apps).

## 2. Build

```bash
git clone <repo> swoosh && cd swoosh
swift build                 # builds the library, CLI, and daemon
```

The first build resolves packages and compiles ~55 modules; expect a
couple of minutes cold, seconds incrementally. Run from the repo with
`swift run swoosh …`, or copy `.build/debug/swoosh` and
`.build/debug/swooshd` onto your `PATH`.

> **ActantDB:** the daemon stores durable state in ActantDB, an
> event-sourced sibling project. `swooshd` spawns the `actantdb` binary
> automatically — if it is not found, build it once
> (`cd ../actantDB && cargo build`) or set `SWOOSH_ACTANTDB_PATH`.

## 3. First run — guided setup

```bash
swift run swoosh setup quick
```

`setup quick` profiles your machine, creates `~/.swoosh/`, and writes a
runtime config (permission profile, tool policy, safety flags). You can
re-run it any time; it is idempotent.

## 4. Configure a model provider

The agent talks to a model. Add an API key for any supported provider:

```bash
swift run swoosh provider auth        # interactive — pick a provider, paste a key
```

Keys are stored in the macOS Keychain (service `ai.swoosh.agent`), never
in plaintext config. Supported today: OpenAI, OpenRouter, a local
OpenAI-compatible endpoint (Ollama, LM Studio, …), and Eliza Cloud.

With no key configured the agent still answers, via a local diagnostic
fallback — useful to confirm wiring, but not a real model.

## 5. Check everything is healthy

```bash
swift run swoosh doctor
```

`doctor` runs ~16 checks across installation, daemon, config, secrets,
model, storage, and privacy. `swoosh doctor --fix` repairs what it can;
`--json` emits machine-readable output.

## 6. Chat from the terminal

```bash
swift run swoosh chat                 # interactive REPL (the default command)
swift run swoosh ask "Summarize the last commit"   # one-shot
```

## 7. Run the daemon

```bash
swift run swooshd                     # foreground; Ctrl-C to stop
swooshd --help                        # options and environment variables
```

`swooshd` binds `127.0.0.1:8787` by default. On first start it mints a
bearer token, prints it, and persists it to `~/.swoosh/api_token`. Every
`/api/*` request requires that token.

To reach the daemon from your iPhone on the same Wi-Fi, bind to the LAN:

```bash
SWOOSH_HOST=0.0.0.0 swift run swooshd
```

The token is still required — the loopback default is defense in depth,
not the only line of defense.

## 8. Pair your iPhone

1. Build and run **SwooshiOS** (`Apps/SwooshiOS`) on your device.
2. In the app, open the drawer → **Settings → Pairing**.
3. Enter the daemon host (`http://<your-mac>.local:8787`) and paste the
   token from `~/.swoosh/api_token`.
4. Tap **Pair**. Chat, Connections, and Settings now load live data.

## 9. Shell completion

`swoosh` ships completion for zsh, bash, and fish — covering every
subcommand, flag, and option:

```bash
swoosh completions zsh --install      # writes the script + prints activation steps
swoosh completions bash --install
swoosh completions fish --install
```

Open a new shell afterwards. `swoosh completions <shell>` (without
`--install`) just prints the script if you prefer to place it yourself.

## 10. Where things live

Everything is under `~/.swoosh/`:

| Path | Contents |
|---|---|
| `config.json` | Runtime configuration |
| `api_token` | Daemon bearer token (mode `0600`) |
| `actant.db` | ActantDB event ledger — sessions, memories, audit |
| `skills/`, `goals/`, `cron/` | Self-improvement state |
| `logs/` | Daemon + ActantDB logs |
| `artifacts/` | Generated media and files |

## 11. Troubleshooting

| Symptom | Fix |
|---|---|
| `swooshd` exits with `FATAL: could not start ActantDB` | See **Bootstrapping `actantdb`** below — the daemon prints the search paths and three fix options when it bails. |
| iPhone can't reach the daemon | Start it with `SWOOSH_HOST=0.0.0.0`; confirm both devices are on the same Wi-Fi. |
| Bearer token rejected | Re-copy `~/.swoosh/api_token` — it changes if the file is deleted. |
| Agent replies but seems generic | No provider key configured — run `swoosh provider auth`. |
| Anything else | `swoosh doctor` first; it names the failing component and a fix command. |

### Bootstrapping `actantdb`

`swooshd` spawns the `actantdb` binary as a child process. On a clean
machine the binary doesn't exist yet, so the daemon prints its search
paths and bails with `exit 1`. Pick one of:

1. **Build it from the sibling repo (most common)**
   ```bash
   cd ../actantDB
   cargo build              # debug — lands in ~/.cache/cargo-actantdb/debug/
   cargo build --release    # release — lands in ../actantDB/target/release/
   ```
   The daemon searches both locations automatically.

2. **Point swooshd at an existing binary**
   ```bash
   SWOOSH_ACTANTDB_PATH=/path/to/actantdb swift run swooshd
   ```

3. **Install it on `PATH`** so `which actantdb` resolves. The
   supervisor falls back to a `PATH` lookup if every search path misses.

The daemon's startup log lists every path it tried before failing, so
you can also just read the error and pick the closest path to where
your binary actually is.

For architecture and design, see `Docs/Architecture.md` and
`Docs/design.md`. For the current readiness assessment, see
`Docs/Audit.md`.
