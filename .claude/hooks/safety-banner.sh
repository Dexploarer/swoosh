#!/usr/bin/env bash
# Swoosh safety banner — PreToolUse reminder for edits to load-bearing files.
# Reads tool input JSON from stdin, prints a stderr banner if the file_path
# matches a sensitive area, exits 0 (non-blocking).
#
# Wired in .claude/settings.json under hooks.PreToolUse with matcher Edit|Write.
# Add new sensitive paths to the case statement below.

set -euo pipefail

input="$(cat)"
# Extract file_path from the JSON tool_input. Use a portable jq fallback so
# missing jq doesn't break the hook.
if command -v jq >/dev/null 2>&1; then
  path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty')"
else
  # Best-effort grep — jq is the right tool but this keeps the hook working
  # on a fresh machine.
  path="$(printf '%s' "$input" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
fi

[ -z "$path" ] && exit 0

banner() {
  local rule="$1"
  printf '\033[1;33m━━━ swoosh safety reminder ━━━\033[0m\n%s\n\033[1;33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n' "$rule" >&2
}

case "$path" in
  *Sources/SwooshFirewall/*)
    banner "Editing SwooshFirewall — the ONLY permission enforcement point.
  • No bypass paths (no \"skip if env=dev\", no \"log-only mode\").
  • Default-deny on unknown permissions and parse errors.
  • Every require() call must produce an AuditEntry — grants and denies both.
  • Constant-time compares on any secret/token comparison."
    ;;
  *Sources/SwooshTools/SwooshPermission.swift)
    banner "Editing SwooshPermission — the permission enum.
  • Adding a case? Also update Docs/PermissionModel.md.
  • Adding a case? Wire it into the matching tool's SwooshTool.permission static.
  • Don't rename existing cases — they're the on-disk permission grant key."
    ;;
  *Sources/SwooshCore/PromptBuilder.swift)
    banner "Editing PromptBuilder — the PRIVACY boundary.
  • Rule #6: rejected memory candidates, raw Scout records, cookies, and
    secrets NEVER enter prompts.
  • Any new context source must funnel through this builder.
  • Set ResponseAuditRecord exclusion flags for any new memory category."
    ;;
  *Sources/SwooshCore/AgentToolLoop.swift|*Sources/SwooshCore/AgentKernel.swift)
    banner "Editing the agent run-loop.
  • Rule #7: crypto tool inputs cannot include private keys, seed phrases,
    cookies, or session tokens.
  • Rule #8: humanOnly tools cannot be executed by model-origin calls.
  • Every step must log via AuditLogging — no print(), no OSLog for state."
    ;;
  *Sources/SwooshScout/*)
    banner "Editing SwooshScout — the personalization scanner.
  • Secret redactor runs BEFORE ActantDB write — don't reorder.
  • New source needs Sensitivity (.high for personal data).
  • Calendar/Reminders are AGGREGATE-ONLY — no titles, attendees, or text.
  • Rejected candidates are purged, never retained."
    ;;
  *Sources/SwooshAPI/*|*Sources/SwooshDaemon/*)
    banner "Editing the daemon API surface.
  • Every /api/* route requires BearerAuthMiddleware.
  • Tokenless startup MUST mount DenyAllMiddleware — don't bypass for dev.
  • Constant-time compare on the token — no plain == on secrets.
  • New wire types go in Sources/SwooshClient/WireTypes.swift, not here."
    ;;
  *Sources/SwooshSecrets/*)
    banner "Editing SwooshSecrets — the secret scavenger.
  • Read order matters: Environment → ConfigFile → Keychain.
  • KeychainSecretStore is the canonical store.
  • Don't log secret values — even at debug level."
    ;;
esac

exit 0
