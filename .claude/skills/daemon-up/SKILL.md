---
name: daemon-up
description: Start swooshd and verify the iPhone pairing path is live. Use when starting the daemon, debugging "iOS can't reach Mac", verifying the bearer token, or checking that ActantDB came up correctly. Encodes the token-resolution order, the deny-all fallback, and the smoke-test curl.
---

# Bring swooshd up and verify pairing

## Start

```bash
swift run swooshd
```

The daemon resolves a bearer token in this order at startup:

1. `SWOOSH_API_TOKEN` env var (if set)
2. `~/.swoosh/api_token` (auto-persisted across runs)
3. Fresh mint via `SecRandomCopyBytes` (printed to log, persisted to `~/.swoosh/api_token`)

If **none** resolves, the entire `/api/*` tree is mounted under `DenyAllMiddleware`. That's defense-in-depth — even an accidentally-public daemon refuses to act.

## Verify the smoke path

In another terminal:

```bash
# Read the persisted token
TOKEN=$(cat ~/.swoosh/api_token)
echo "$TOKEN" | head -c 8; echo "…"

# Hit the chat endpoint
curl -sS http://127.0.0.1:7777/api/agent/chat \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"ping"}]}' \
  | head -50
```

(Port is 7777 by default; check the startup banner if it's been overridden.)

## What "up" actually means

`swooshd` startup involves these steps in order — if any fails, the daemon won't fully serve:

1. `ActantDBSupervisor` spawns `actantdb serve` as a child process. Sets `ACTANT_BASE_URL` env var.
2. `Swoosh.configure { _ in }` builds the default kernel against ActantDB.
3. `BundledSkillLoader` loads `Skills/Bundled/*.md` into the `FileSkillStore` with deterministic IDs (`bundled.<filename>`).
4. `AppUsageRecorder` starts the `NSWorkspace` observer writing to `~/.swoosh/app-usage.jsonl`.
5. `SwooshAPIServer(port:hostname:token:kernel:)` mounts routes.
6. Banner prints token, host, port.

## Common failures

- **"address already in use"** — another `swooshd` is running. `lsof -i :7777` to find the PID, then decide whether to kill or pair with the existing instance.
- **`/api/*` returns 401 even with the token** — token mismatch. Verify with `launchctl getenv SWOOSH_API_TOKEN` (if set there) vs `cat ~/.swoosh/api_token`. The constant-time compare doesn't tell you which side is wrong.
- **`/api/*` returns 404 across the board** — `DenyAllMiddleware` is mounted (token didn't resolve at startup). Restart with `SWOOSH_API_TOKEN=$(openssl rand -hex 32)` to force a token in.
- **ActantDB stuck** — check `~/.swoosh/logs/` for the supervisor's child output. The child crashes leave a backoff loop in `ActantDBSupervisor`; killing the parent daemon is the cleanest reset.
- **iPhone gets "could not connect"** — check that Info.plist `NSLocalNetworkUsageDescription` permission was granted (Settings → Privacy → Local Network → SwooshiOS). The first launch prompts; if denied, the path is unrecoverable without revoking-and-relaunching.

## Bind address (`SWOOSH_HOST`)

Default is `127.0.0.1` (loopback only). LAN exposure requires `SWOOSH_HOST=0.0.0.0` — bearer auth is still required, but only opt in deliberately. **Never** bind to `0.0.0.0` on an untrusted network.
