#!/bin/sh
# Hello Exec plugin — reference implementation of Swoosh's executable
# plugin ABI. Reads one JSON request from stdin and writes one JSON
# response to stdout. No state, no network, no files.
#
# Request shape :  {"tool":"<name>","args":{...}}
# Response shape:  {"ok":true,"output":<value>} OR {"ok":false,"error":"..."}
#
# Implementation is pure /bin/sh + awk so the demo works on every macOS
# install without a Python or Node dep.

set -eu

# Read stdin verbatim.
request=$(cat)

# Best-effort field extraction. The plugin doesn't need to fully parse
# JSON — it just locates the `tool` value and echoes the entire `args`
# field back. A real plugin would use jq / a JSON library.
tool=$(printf '%s' "$request" | awk '
    {
        # Match the first "tool": "<value>" occurrence
        if (match($0, /"tool"[[:space:]]*:[[:space:]]*"[^"]*"/)) {
            s = substr($0, RSTART, RLENGTH)
            sub(/.*"tool"[[:space:]]*:[[:space:]]*"/, "", s)
            sub(/".*/, "", s)
            print s
            exit
        }
    }
')

args=$(printf '%s' "$request" | awk '
    BEGIN { capturing = 0; depth = 0; out = "" }
    {
        line = $0
        while (length(line) > 0) {
            if (capturing == 0) {
                idx = index(line, "\"args\"")
                if (idx == 0) { line = ""; continue }
                line = substr(line, idx + 6)
                colon = index(line, ":")
                if (colon == 0) { line = ""; continue }
                line = substr(line, colon + 1)
                # Skip whitespace
                sub(/^[[:space:]]+/, "", line)
                capturing = 1
            }
            for (i = 1; i <= length(line); i++) {
                ch = substr(line, i, 1)
                if (capturing == 1) {
                    if (ch == "{") { depth = 1; capturing = 2; out = "{" }
                    else if (ch == "[") { depth = 1; capturing = 3; out = "[" }
                    else { out = out ch; if (ch == "," || ch == "}") { capturing = 0; print out; exit } }
                } else if (capturing == 2) {
                    out = out ch
                    if (ch == "{") depth++
                    else if (ch == "}") { depth--; if (depth == 0) { print out; exit } }
                } else if (capturing == 3) {
                    out = out ch
                    if (ch == "[") depth++
                    else if (ch == "]") { depth--; if (depth == 0) { print out; exit } }
                }
            }
            line = ""
        }
    }
')

if [ -z "$tool" ]; then
    printf '{"ok":false,"error":"missing tool field"}\n'
    exit 0
fi

case "$tool" in
    "exec.echo")
        # Construct the response. `args` is already JSON; embed verbatim.
        if [ -z "$args" ]; then args="null"; fi
        printf '{"ok":true,"output":{"echoed":%s,"tool":"%s","pluginID":"hello-exec"}}\n' "$args" "$tool"
        ;;
    *)
        printf '{"ok":false,"error":"unknown tool: %s"}\n' "$tool"
        ;;
esac
