#!/usr/bin/env bash
# Swoosh prompt enhancer — UserPromptSubmit hook.
# Takes the raw user prompt, gathers compact session context, and asks a fast
# Claude (Haiku by default) to REWRITE the prompt into a clearer, more
# specific version that resolves pronouns, expands implied file paths, and
# carries forward constraints from recent turns. The rewrite is injected as
# additionalContext alongside the original — Claude reads BOTH.
#
# Context sources:
#   - .remember/now.md  (the live activity buffer)
#   - The last ~3 assistant turns from this session's transcript
#   - git: current branch, last 2 commits, unstaged count
#
# Hard guards (the hook MUST never harm the UX):
#   - Skip on short prompts (<10 chars) — pointless and slow
#   - Skip on slash commands (start with /) — those are CLI directives
#   - Skip on very long prompts (>2000 chars) — already specific
#   - Infinite-loop guard: child claude call runs with PROMPT_ENHANCER=off
#   - Timeout cap (default 15s) — never hang the prompt forever
#   - Fail-open silently on ANY error (missing claude, jq parse error, etc.)
#
# Toggle off per-shell:    PROMPT_ENHANCER=off
# Tune model:              PROMPT_ENHANCER_MODEL=haiku|sonnet|opus  (default haiku)
# Tune timeout:            PROMPT_ENHANCER_TIMEOUT=15  (seconds)
# Tune output cap:         PROMPT_ENHANCER_MAX_BYTES=3000
#
# Wired in .claude/settings.json under hooks.UserPromptSubmit.

set -uo pipefail  # NOT -e — must never block on a sub-command failure

# ── infinite-loop guard ─────────────────────────────────────────────────
# The child `claude -p` call below would otherwise re-fire this hook.
[ "${PROMPT_ENHANCER:-on}" = "off" ] && exit 0

MAX_BYTES="${PROMPT_ENHANCER_MAX_BYTES:-4000}"
TIMEOUT_S="${PROMPT_ENHANCER_TIMEOUT:-60}"
MODEL="${PROMPT_ENHANCER_MODEL:-sonnet}"

input="$(cat 2>/dev/null || true)"

# Required tools — fail open silently if missing
command -v jq     >/dev/null 2>&1 || exit 0
command -v claude >/dev/null 2>&1 || exit 0

# Cross-platform timeout: prefer GNU timeout / gtimeout (from coreutils),
# fall back to perl's alarm + exec (always installed on macOS / most *nix).
run_with_timeout() {
  local secs="$1"; shift
  if command -v timeout  >/dev/null 2>&1; then timeout  "$secs" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$secs" "$@"
  elif command -v perl     >/dev/null 2>&1; then
    # Start the child in its own process group so SIGALRM can SIGKILL
    # the whole group — otherwise a hung `claude` process would be
    # orphaned when perl's alarm fires.
    perl -e '
      use POSIX qw(setsid);
      my $secs = shift @ARGV;
      my $pid = fork();
      if ($pid == 0) { setsid(); exec(@ARGV) or exit 127; }
      $SIG{ALRM} = sub { kill("KILL", -$pid); exit 124; };
      alarm $secs;
      waitpid($pid, 0);
      exit($? >> 8);
    ' "$secs" "$@"
  else "$@"
  fi
}

prompt="$(printf '%s'     "$input" | jq -r '.prompt // empty'          2>/dev/null || true)"
transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
cwd="$(printf '%s'        "$input" | jq -r '.cwd // empty'             2>/dev/null || true)"
[ -z "$cwd" ] && cwd="${CLAUDE_PROJECT_DIR:-$PWD}"

# ── skip rules ─────────────────────────────────────────────────────────
[ -z "$prompt" ] && exit 0
case "$prompt" in
  /*) exit 0 ;;          # slash command — leave alone
esac
plen="${#prompt}"
if [ "$plen" -lt 10 ] || [ "$plen" -gt 2000 ]; then
  exit 0
fi

repo_root="$(cd "$cwd" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || true)"
[ -z "$repo_root" ] && repo_root="$cwd"

# ── gather context (cheap, deterministic) ──────────────────────────────
now_buf=""
if [ -f "$repo_root/.remember/now.md" ]; then
  now_buf="$(head -n 30 "$repo_root/.remember/now.md" 2>/dev/null || true)"
fi

recent_md=""
if [ -f "$repo_root/.remember/recent.md" ]; then
  recent_md="$(head -n 25 "$repo_root/.remember/recent.md" 2>/dev/null || true)"
fi

recent_turns=""
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  # Pull richer assistant turn summaries — slightly longer per-turn budget so
  # Sonnet has enough to ground pronouns and implied references.
  recent_turns="$(
    tail -n 800 "$transcript" 2>/dev/null \
      | jq -r '
          select(.type == "assistant")
          | (.message.content // .content // empty)
          | if type == "array" then
              ( [ .[]
                  | if   .type == "text"     then ((.text // "") | gsub("\\s+"; " ") | .[0:260])
                    elif .type == "tool_use" then "→\(.name // "tool")(\(.input.file_path // .input.command // .input.pattern // "") | .[0:60])"
                    else empty end ]
                | map(select(. != null and . != ""))
                | join(" | ")
                | .[0:420] )
            else empty end' 2>/dev/null \
      | grep -v '^$' \
      | tail -n 4 \
      | awk '{printf "- %s\n", $0}'
  )"
fi

repo_pulse=""
modified_files=""
if [ -d "$repo_root/.git" ]; then
  branch="$(git -C "$repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")"
  unstaged="$(git -C "$repo_root" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  commits="$(git -C "$repo_root" log --oneline -3 2>/dev/null)"
  modified_files="$(git -C "$repo_root" status --porcelain 2>/dev/null | head -10 | awk '{printf "- %s\n", $0}')"
  repo_pulse="branch=$branch · unstaged=$unstaged
$commits"
fi

# ── build the rewrite meta-prompt ──────────────────────────────────────
# Uses `read -d ''` (canonical bash heredoc-to-variable idiom) because
# `meta=$(cat <<EOF ... EOF)` is parsed weirdly when the body contains
# apostrophes / parens — bash`s $() parser scans the heredoc body for
# matching delimiters even though it should be opaque.
IFS='' read -r -d '' meta <<MPROMPT || true
You are a prompt structurer for Claude Code working on the Swoosh codebase (Swift, macOS 26 / iOS 26, agent runtime: SwooshKit + swooshd daemon + swoosh CLI + menu-bar Mac app + iOS companion). The user just typed a prompt. Rewrite it into a STRUCTURED, ACTIONABLE brief using the session context below.

OUTPUT FORMAT (use these section headers exactly, omit a section only if it truly does not apply):

Goal: <one sentence — verb + object>
Targets:
- <file path / module / symbol>: <why it matters here>
- <…>
Carried-from-context:
- <constraint or fact from .remember/ or recent turns the user clearly still wants applied>: <where it came from>
- <…>
Done means:
- <concrete acceptance criterion>
- <…>
Out of scope:
- <obvious non-goal, only if implied>
Open questions:
- [unclear: <only if genuinely blocking>]

HARD RULES:
- Resolve pronouns ("it", "this", "that", "the bug", "the file", "the hook", "the test") using the context. NEVER pass them through unresolved.
- Spell out file paths, module names, function names, permission cases, tool names — even if the user abbreviated.
- "Carried-from-context" is the most valuable section: pull constraints/decisions/in-flight work from .remember/now.md and recent assistant turns that the user clearly still wants honored.
- Do NOT invent new requirements. ONLY rewrite + structure it.
- **NEVER ANSWER THE PROMPT.** Your job is restructure-only. Even if the prompt is a trivia question, a math problem, a factual question — DO NOT ANSWER IT. Treat every input as a task brief to be clarified, not a question to respond to. If you cannot rewrite it as a Swoosh codebase task, output the literal prompt verbatim with NO section labels.
- If the prompt is already a fully-specified brief (every section would be trivially derivable from the prompt alone with no pronouns), output the literal prompt verbatim with no structure.
- Output rule: EITHER your first line is exactly "Goal: <one sentence>" (full structured rewrite) OR output the input prompt verbatim with no other text. Nothing else is valid.
- Output is plain text using the EXACT section labels above. NO markdown (no #, no **bold**, no --- separators, no asterisks). NO preamble ("Based on…", "Here is the rewritten…", "Here's the structured prompt"). NO trailing commentary. Begin output with the literal word "Goal:" — no whitespace, no characters before it.
- Keep total output under ~30 lines.

# Raw user prompt
$prompt

# .remember/now.md (live activity buffer — most recent first)
$now_buf

# .remember/recent.md (last 7 days summary)
$recent_md

# Last 4 assistant turns this session (text snippets | tool calls with first arg)
$recent_turns

# Repo pulse (branch · unstaged count · last 3 commits)
$repo_pulse

# Currently modified files (git status, first 10)
$modified_files
MPROMPT

# ── call claude -p with infinite-loop guard + timeout ──────────────────
# stdin MUST be /dev/null — the hook's own stdin was consumed by `cat` above,
# but `claude -p` still blocks ~3s waiting for stdin EOF if not explicitly
# redirected. That race causes intermittent empty returns.
enhanced="$(
  PROMPT_ENHANCER=off run_with_timeout "$TIMEOUT_S" \
    claude -p --model "$MODEL" "$meta" </dev/null 2>/dev/null || true
)"

# Fail-open: if the rewrite is empty, errored, or basically the same as the input, do nothing.
if [ -z "$enhanced" ]; then exit 0; fi
# Trim leading/trailing whitespace for comparison
trimmed="$(printf '%s' "$enhanced" | awk 'NF{p=1} p' | sed 's/[[:space:]]*$//')"
if [ -z "$trimmed" ]; then exit 0; fi
# If model echoed the prompt verbatim (already-clear case), don't bother injecting
if [ "$trimmed" = "$prompt" ]; then exit 0; fi
# Validate output shape: must contain "Goal:" within the first 300 chars
# (tolerates a small preamble or markdown variants like **Goal:**) OR equal
# the input prompt verbatim. Anything else (e.g. the model answered the
# question instead of rewriting) is a failed rewrite — skip injection.
if ! printf '%s' "$trimmed" | head -c 300 | grep -q "Goal:"; then
  exit 0
fi
# Strip any leading preamble / markdown that came before the first "Goal:"
# line, so the injection always starts cleanly at the structured rewrite.
enhanced="$(printf '%s' "$enhanced" | awk '/Goal:/{found=1} found' | sed 's/\*\*//g')"

# Cap injected size
if [ "${#enhanced}" -gt "$MAX_BYTES" ]; then
  enhanced="$(printf '%s' "$enhanced" | head -c "$MAX_BYTES")
… (truncated by prompt-enhancer at ${MAX_BYTES} bytes)"
fi

# Inject as additionalContext — Claude reads BOTH the original prompt and this.
cat <<OUT
<prompt-enhancer source="context-aware-rewrite" model="$MODEL">
The user's prompt rewritten with this session's context for clarity. Treat as a more specific restatement — if it conflicts with the literal prompt, the literal prompt wins.

$enhanced
</prompt-enhancer>
OUT

exit 0
