#!/bin/bash
# learnings-context.sh — SessionStart hook
# Loads .superstack/learnings.md into session context so past patterns/pitfalls
# surface automatically. Silently no-ops if the file is missing or empty.

set -euo pipefail

LEARNINGS_FILE="${CLAUDE_PROJECT_DIR:-$(pwd)}/.superstack/learnings.md"
[ -f "$LEARNINGS_FILE" ] || exit 0

# Count entries (### kebab-case-key headers). Skip output if none.
COUNT=$(grep -c '^### ' "$LEARNINGS_FILE" 2>/dev/null || true)
[ -z "${COUNT:-}" ] && COUNT=0
[ "$COUNT" -eq 0 ] && exit 0

cat <<HEADER
=== Project learnings (.superstack/learnings.md, $COUNT entries) ===
Patterns, pitfalls, and preferences captured across prior sessions.
Use \`/learn\` to view/search, \`/learn add\` to capture new entries.
Apply these when relevant; latest entry wins on conflicts.

HEADER

cat "$LEARNINGS_FILE"

echo ""
echo "=== End project learnings ==="
