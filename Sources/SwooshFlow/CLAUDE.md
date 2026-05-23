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
| `WorkflowExecutionEngine` | Drafts run through `WorkflowDraft05A` + the `WorkflowDraftStoring` / `WorkflowRunStoring` pair. Writes a `WorkflowRunRecord` per step. |
| `WorkflowDryRunEngine`    | Plans without side effects. Preview before approving destructive workflows. |
| `WorkflowReplayEngine`    | Replays a recorded trace. |

Don't merge them. The separation is what lets dry-run be safe and replay be deterministic.

## How runtime `workflow.run` reaches SwooshFlow

The model-callable `workflow.run` tool lives in `SwooshToolsets/WorkflowTools.swift` and routes through `ToolDependencies.workflowStepExecutor`. The daemon and CLI wire that to `RegistryWorkflowStepExecutor` (in `SwooshTools/ToolRegistry.swift`), which in turn:

1. Executes each step via the firewall-gated `ToolRegistry` (rule #2).
2. Hands the per-step result to an optional `traceRecorder: any TraceRecording?` (protocol in `SwooshTools/TraceRecording.swift`) so the run is auditable.

The concrete recorder is `InMemoryWorkflowTraceRecorder` from this module (`SwooshFlow/WorkflowTraceRecorder.swift`). The daemon and CLI inject it at startup. Adding a durable backend later (ActantDB) is a swap of `TraceRecording` conformer — no caller changes.

## Triggers

`WorkflowTrigger` (in `WorkflowTriggerTypes.swift`) is the canonical trigger taxonomy used by `WorkflowRunner`, `WorkflowTriggerDispatch`, and `WorkflowTriggerRuntime`. `WorkflowTrigger05A` (in `WorkflowDraftModel.swift`) is the projection embedded inside a draft. Both stay.

`WorkflowTriggerLegacy` was a stillborn enum on the bare `Workflow` type. That type and its trigger were never wired to anything and were removed in 0.5E. **Do not reintroduce a third trigger taxonomy** — extend the existing two if a new kind is needed.

New triggers need:
- A trace event so the dispatch itself is auditable.
- A test in `Tests/SwooshFlowTests/` proving the trigger fires once and only once per matching event.

## See also

- The `replay-workflow` skill in `.claude/skills/` for the live debug procedure.
- Engineering rule #4 in root `CLAUDE.md`.
- `SwooshTools/TraceRecording.swift` for the protocol used by the live runtime.
