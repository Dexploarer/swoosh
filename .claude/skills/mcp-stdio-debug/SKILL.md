---
name: mcp-stdio-debug
description: Diagnose stdio MCP transport failures and hangs in Swoosh. Use when an MCP child process hangs, when SwooshMCP tests deadlock, when "Test run with N tests passed" prints but the runner never exits, or when stdio MCP tools fail to round-trip. Encodes the cooperative-pool deadlock pattern fixed in e087609.
---

# Diagnosing stdio MCP failures

The stdio MCP transport (`Sources/SwooshMCP/MCPTransport.swift`) had a long-lived cooperative-pool deadlock that was fixed in `e087609` (2026-05-21). The fix pattern matters because it generalizes.

## The pattern (recognize it elsewhere)

**Symptom.** Code that uses `FileHandle.read(upToCount:)` (or any blocking syscall) inside `Task.detached` — or worse, inside an actor method — will park a thread on the Swift cooperative pool. The pool has ~CPU-count threads; a handful of blocked reads can starve the dispatcher of the threads it needs to handle in-flight actor hops. Result: the very actor that's supposed to forward the response that would unblock the read is itself blocked because there's no pool thread to dispatch its message.

**Fix shape.** Move the blocking syscall **off** the cooperative pool. For `FileHandle`, use `readabilityHandler` — the callback runs on `FileHandle`'s private dispatch queue. For sockets, use a non-blocking pattern (kqueue, NIO).

## Triage recipe

When a SwooshMCP test (or any test that spawns MCP children) hangs:

1. **Find the PID.** `ps -ef | grep swift-test | grep -v grep` — or `pgrep -f "swift-test"`.
2. **Sample it.** `sample <PID> 2 -file /tmp/mcp-sample.txt`.
3. **Open the sample.** `head -200 /tmp/mcp-sample.txt` — look for thread states.
4. **Read the call stacks.**
   - Cooperative thread parked in `__read` / `handle.read(upToCount:)` / any blocking syscall → that's the leak. Fix as above.
   - 10 threads named `NIO-SGLTN-1-#N` parked in `kevent` → **ignore**. SwiftNIO's singleton EventLoopGroup; designed to be persistent; does not block process exit.
   - Threads in `dispatch_mach_msg_send` waiting on something → look at what they're waiting on (usually the runner is waiting for the test process which is waiting for an MCP child).

## After the fix

Always verify:
```bash
swift test --filter SwooshMCPTests
swift test --filter "SwooshMCPTests.MCPStdioEndToEndTests/fullStdioFlow"
```

Then run the full suite to confirm no regression elsewhere:
```bash
swift test
```

## Adjacent hygiene (don't skip)

The fix also requires:
1. **Parent-side write-end closing** in `start()` so the child's read end gets EOF when the child exits cleanly.
2. **Explicit stderr-handle close** in `close()` so the parent doesn't hold stderr open across a transport teardown.

These adjacent fixes prevent zombie children that show up as "stale `actantdb` processes still running after daemon shutdown."

## When in doubt

The bundled `swift-concurrency-triage` skill (`Skills/Bundled/swift-concurrency-triage.md`) covers the broader Sendable / actor-isolation question. Use it for `Sendable` errors; use this skill specifically for hangs and stdio transport bugs.
