#!/usr/bin/env bash
# Swoosh LOC guard — PreToolUse enforcement for the file-size convention.
# CLAUDE.md convention: aim for <350 LOC, hard ceiling 400.
#
# Behavior:
#   - Only fires on Edit / Write tool calls targeting *.swift files in Sources/, Apps/, App/.
#   - Predicts post-edit line count when possible (Edit: current ± diff; Write: new content).
#   - Soft-warn at >=350 (stderr banner, exit 0 — does not block).
#   - Hard-block at >400 (exit 2 with reason; PreToolUse exit 2 blocks the call).
#   - Override per-invocation by setting LOC_GUARD=off in the env.
#   - Override threshold by setting LOC_GUARD_MAX / LOC_GUARD_WARN.
#
# Wired in .claude/settings.json under hooks.PreToolUse with matcher Edit|Write.

set -euo pipefail

[ "${LOC_GUARD:-on}" = "off" ] && exit 0

WARN="${LOC_GUARD_WARN:-350}"
MAX="${LOC_GUARD_MAX:-400}"

input="$(cat)"

# Extract tool name + file_path + content/new_string. Prefer jq; fall back to sed.
# Any jq parse failure → empty string → fail-open (this hook never blocks on
# malformed input; only on a real over-limit Swift file).
if command -v jq >/dev/null 2>&1; then
  tool="$(printf '%s' "$input"  | jq -r '.tool_name // empty' 2>/dev/null || true)"
  path="$(printf '%s' "$input"  | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
  content="$(printf '%s' "$input" | jq -r '.tool_input.content // empty' 2>/dev/null || true)"
  new_str="$(printf '%s' "$input" | jq -r '.tool_input.new_string // empty' 2>/dev/null || true)"
  old_str="$(printf '%s' "$input" | jq -r '.tool_input.old_string // empty' 2>/dev/null || true)"
else
  tool="$(printf '%s' "$input"  | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  path="$(printf '%s' "$input"  | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  content=""
  new_str=""
  old_str=""
fi

# Only act on Edit / Write to Swift files in source dirs.
[ "$tool" != "Edit" ] && [ "$tool" != "Write" ] && exit 0
case "$path" in
  *.swift) ;;
  *) exit 0 ;;
esac
case "$path" in
  */Sources/*|*/Apps/*|*/App/*) ;;
  *) exit 0 ;;
esac

count_lines() { printf '%s' "$1" | awk 'END{print NR}'; }
count_lines_file() {
  # Same logic as count_lines but on a file path — handles missing
  # trailing newline so it matches the in-memory count_lines.
  awk 'END{print NR}' "$1"
}

predicted=0
if [ "$tool" = "Write" ]; then
  predicted="$(count_lines "$content")"
elif [ "$tool" = "Edit" ]; then
  if [ -f "$path" ]; then
    current="$(count_lines_file "$path" | tr -d ' ')"
    old_n="$(count_lines "$old_str")"
    new_n="$(count_lines "$new_str")"
    # Edit replaces old_string (which exists in the file) with new_string.
    # Delta is roughly (new_n - old_n) lines, but only if the old_string is at
    # least one full line. Compute the net change.
    delta=$(( new_n - old_n ))
    predicted=$(( current + delta ))
  else
    # Editing a file that doesn't exist will fail anyway — let the tool report it.
    exit 0
  fi
fi

[ "$predicted" -le 0 ] && exit 0

banner() {
  local color="$1" title="$2" body="$3"
  printf '\033[1;%sm━━━ loc-guard: %s ━━━\033[0m\n%s\n\033[1;%sm━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n' \
    "$color" "$title" "$body" "$color" >&2
}

rel="${path##*/swoosh/}"

if [ "$predicted" -gt "$MAX" ]; then
  banner 31 "BLOCK" "$rel would be ~${predicted} LOC after this edit (ceiling is ${MAX}).
File-size convention (CLAUDE.md): split along a real seam — separate type,
separate responsibility. Not arbitrary chunking.

Override for one call:  LOC_GUARD=off
Raise ceiling for repo: set LOC_GUARD_MAX in .claude/settings.json env."
  exit 2
fi

if [ "$predicted" -ge "$WARN" ]; then
  banner 33 "warn" "$rel would be ~${predicted} LOC after this edit (warn at ${WARN}, ceiling ${MAX}).
Consider splitting before this file grows further."
  exit 0
fi

exit 0
