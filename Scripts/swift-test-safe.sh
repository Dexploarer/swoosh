#!/usr/bin/env bash
# Scripts/swift-test-safe.sh — wrap `swift test` with orphan-kill on signal
#
# When swift test is launched via the Claude Code Bash tool, the tool may
# auto-background long-running commands. If the parent task is later
# cancelled (timeout, /stop, user interrupt) the wrapping zsh dies but
# child `swift-test` + `swiftpm-testing-helper` processes survive,
# reparent to PID 1, hold `.build/`'s SwiftPM lock, and silently block
# every subsequent `swift test` in this repo until they are manually
# `kill -9`'d.
#
# This wrapper installs a TERM/INT/HUP/EXIT trap that walks the process
# tree from $$ downward and SIGKILLs every descendant, so the SwiftPM
# lock is always released even when the parent shell is signal-killed.
# (It cannot help if the wrapper itself is SIGKILL'd — but the Bash tool
# uses SIGTERM, which the trap catches.)
#
# Usage:
#   ./Scripts/swift-test-safe.sh                       # run full suite
#   ./Scripts/swift-test-safe.sh --filter SwooshCron   # filter argument
#
# Pass any flags `swift test` accepts; they are forwarded verbatim.

set -m  # enable job control so children get their own process group

kill_tree() {
    local pid=$1 kids
    kids=$(pgrep -P "$pid" 2>/dev/null) || true
    for k in $kids; do
        kill_tree "$k"
    done
    kill -9 "$pid" 2>/dev/null || true
}

cleanup() {
    local kids
    kids=$(pgrep -P $$ 2>/dev/null) || true
    for k in $kids; do
        kill_tree "$k"
    done
}

trap cleanup EXIT INT TERM HUP

cd "$(git rev-parse --show-toplevel)"
swift test "$@"
