---
name: replay-workflow
description: Replay a SwooshFlow workflow run to debug non-determinism, tool failures, or audit divergence. Use when a workflow produced unexpected output, when "the same input gave a different result", or when investigating a /why response that points at a flow trace.
---

# Replaying a workflow

`SwooshFlow` records a deterministic trace of every workflow execution. Every workflow is replayable; this is engineering rule #4.

## When to replay

- A workflow produced wrong output and you need to see which step diverged.
- The user complained "the same prompt gave a different answer" — replay both runs and diff.
- A `humanOnly` approval inside a workflow looked wrong; replay shows the exact tool input that was presented.
- You're auditing an incident and need the per-step trace, not just the final response.

## Engine layout

| Engine | Purpose |
|---|---|
| `WorkflowExecutionEngine` | Live runs. Writes the trace. |
| `WorkflowDryRunEngine` | Plans without side effects. Use to preview before approving destructive workflows. |
| `WorkflowReplayEngine` | Replays a recorded trace deterministically. |

All three live in `Sources/SwooshFlow/`.

## Replay procedure

1. **Locate the trace.** Workflow traces live on ActantDB alongside session messages. The fastest path:
   ```bash
   swift run swoosh memory list --kind workflow-trace | head -20
   ```
   Or query ActantDB directly via the agent's `/why` surface.
2. **Identify the run ID** from the trace.
3. **Replay** via `WorkflowReplayEngine`:
   - In a test: see `Tests/SwooshFlowTests/WorkflowReplayTests.swift` for the canonical pattern.
   - In a live CLI session: not yet exposed via `swoosh` subcommand — write the replay test instead, that's the supported entry point today.
4. **Diff.** The replay should produce byte-identical output. If it doesn't, you've found non-determinism:
   - **Timestamps in tool output** — tools must not embed `Date()` in their `Output`. Replace with explicit `at:` parameter.
   - **`Set` ordering** — collections must be `[String]` sorted, not `Set<String>`, for any output that crosses the boundary.
   - **Random IDs** — generate at the call site, not inside the tool.

## Pitfalls

- **Replaying with a different model** changes outputs by design (model_change_invalidates_replay is a known limitation). Pin the model in the replay request.
- **Replaying with different tools registered** — same story. Replay against the exact toolset that produced the trace.
- **Trace tampering.** Traces should be append-only on ActantDB; if you see a modified trace, treat it as an integrity issue, not a replay bug.

## Related

- `Sources/SwooshFlow/WorkflowReplayRun.swift` — the type holding a replay-in-progress.
- `Sources/SwooshFlow/WorkflowExecutionTypes.swift` — the trace event schema.
- Engineering rule #4 (every workflow is replayable) and rule #5 (every memory is inspectable via `/why`) — these two together are the agent's accountability story.
