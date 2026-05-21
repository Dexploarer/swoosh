---
name: run-swoosh-tests
description: How to run the Swoosh test suite efficiently. Use when running swift test, narrowing to a single target, debugging a "hang at 100% passed" runner, or asked "did I break X". Encodes the multi-filter hang limitation, the cooperative-pool deadlock pattern fixed in e087609, and expected walltimes.
---

# Running the Swoosh test suite

~50 test targets, 1749 swift-testing tests, ~10–15s walltime after a fresh build (~2s incremental). Full `swift test` works cleanly as of `e087609`.

## Pick the right command

| Goal | Command |
|---|---|
| "Does it compile" | `swift build` |
| "Is the tree healthy" | `swift test` |
| "Did I break module X" | `swift test --filter <Module>Tests` |
| One specific test | `swift test --filter "<Target>.<Suite>/<test>"` |
| Discover test IDs | `swift test --list-tests \| grep <substr>` |

`--filter` takes the **test ID** from `--list-tests`, not the display name. `"Initialize completes"` will match nothing.

## Hard limitations

- **Multiple `--filter` flags in one invocation hang at startup with 0% CPU.** Loop in shell instead:
  ```bash
  for t in SwooshFirewallTests SwooshAgentLoopTests SwooshFlowTests; do
    echo "=== $t ==="
    swift test --filter $t 2>&1 | grep "Test run" | tail -1
  done
  ```

## Hang triage (cooperative-pool deadlock pattern)

Symptom: tests all print "passed", then the runner sits at 0% CPU indefinitely and never exits.

Recipe:
1. `ps -ef | grep swift-test` to get the PID.
2. `sample <PID> 2 -file /tmp/sample.txt && head -200 /tmp/sample.txt`
3. Look for cooperative threads parked in `handle.read(upToCount:)` or any blocking syscall. Any blocking read inside `Task.detached` will starve the pool — fix by moving it to `FileHandle.readabilityHandler` (callback runs on FileHandle's private dispatch queue). See `Sources/SwooshMCP/MCPTransport.swift` for the canonical fix.
4. **Ignore** `NIO-SGLTN-1-#N` threads parked in `kevent` — those are SwiftNIO's process-wide singleton EventLoopGroup, not a hang cause.

## Pitfalls

- Don't add `swift test --parallel` — the default already parallelizes; the flag has historically destabilized the stdio MCP path.
- Don't shell out to `xcodebuild test` for library/CLI/daemon work — it's slower and won't pick up package-level changes without scheme regeneration. Use `swift test`.
- `swift test --enable-code-coverage` slows the run significantly; reserve for explicit coverage passes.
