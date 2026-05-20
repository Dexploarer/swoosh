#!/bin/sh
input=$(cat)
command=$(printf '%s' "$input" | python3 -c 'import json,sys
try:
    data=json.load(sys.stdin)
except Exception:
    data={}
tool_input=data.get("tool_input", data)
print(tool_input.get("command", "") or tool_input.get("cmd", ""))' 2>/dev/null || true)

[ -z "$command" ] && exit 0

context=""
case "$command" in
  *"git stash"*|*"git reset --hard"*|*"git clean -f"*|*"git checkout --"*|*"git switch "*|*"git checkout "*)
    context="Swoosh git rule: do not stash, discard, switch branches, or run destructive cleanup unless the user explicitly asked for that exact operation. Preserve the current dirty worktree."
    ;;
  *"Swoosh.xcodeproj"*|*".xcodeproj"*)
    case "$command" in
      *"xcodegen generate"*|*"xcodebuild -project"*) ;;
      *) context="Swoosh project rule: Swoosh.xcodeproj is generated from project.yml. Edit project.yml and run xcodegen generate instead of hand-editing the project." ;;
    esac
    ;;
  *"swift build"*|*"swift test"*|*"xcodebuild"*)
    context="Swoosh verification: SwiftPM is the default gate for library, CLI, and daemon work. Use xcodegen after project.yml changes, and use CODE_SIGNING_ALLOWED=NO for SwooshiOS simulator builds."
    ;;
  *"grep "*|*"find "*|*"ack "*|*"ag "*|*"ripgrep "*)
    context="Swoosh search rule: prefer rg or rg --files for repo search unless a different tool is required by the task."
    ;;
esac

[ -z "$context" ] && exit 0

CONTEXT="$context" python3 -c 'import json, os
print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":os.environ["CONTEXT"]}}))'
