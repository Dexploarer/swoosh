# SwooshFlow

The workflow engine. Loaded automatically when Claude edits here.

## The replay invariant (engineering rule #4)

Every workflow run is replayable byte-for-byte from its trace. This is load-bearing for incident debugging and `/why` audits. Code that breaks replay is broken.

## Sources of non-determinism (forbidden in trace-touching output)

- `Date()` / `Date.now` inside a tool's `Output`. If a timestamp is needed, accept it as an `Input` parameter set by the executor.
- `Set<T>` ordering. Sort to `[T]` before placing in `Output`.
- `Dictionary` iteration order. Same fix.
- `UUID()` minted inside a tool. Mint at the call site; pass in as `Input`.
- Time-dependent control flow ("if it's after 5pm…"). Encode the threshold as an `Input` and let the executor decide.
- Network responses without a recorded fixture. The replay engine doesn't re-hit the network; if your trace embeds a live response, the replay diverges.

## Three engines, three uses

| Engine | When |
|---|---|
| `WorkflowExecutionEngine` | Live runs. Writes the trace. |
| `WorkflowDryRunEngine` | Plans without side effects. Preview before approving destructive workflows. |
| `WorkflowReplayEngine` | Replays a recorded trace. |

Don't merge them. The separation is what lets dry-run be safe and replay be deterministic.

## Triggers

`WorkflowTrigger*` types dispatch workflows from external events. New triggers need:
- A trace event so the dispatch itself is auditable.
- A test in `Tests/SwooshFlowTests/` proving the trigger fires once and only once per matching event.

## See also

- The `replay-workflow` skill in `.claude/skills/` for the live debug procedure.
- Engineering rule #4 in root `CLAUDE.md`.
