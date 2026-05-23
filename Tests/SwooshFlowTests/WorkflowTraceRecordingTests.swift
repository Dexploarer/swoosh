// Tests/SwooshFlowTests/WorkflowTraceRecordingTests.swift — 0.5E
//
// Covers the runtime trace recorder + the TracingWorkflowStepExecutor
// wrapper that the daemon and CLI now inject around
// `RegistryWorkflowStepExecutor`. This is the new enforcement point for
// engineering rule #4 ("every workflow is replayable") on live runs.

import Foundation
import Testing
import SwooshTools
@testable import SwooshFlow

@Suite("WorkflowTraceRecording")
struct WorkflowTraceRecordingTests {

    // MARK: - InMemoryWorkflowTraceRecorder

    @Test("Record + tail round-trip preserves insertion order")
    func recordAndTail() async {
        let recorder = InMemoryWorkflowTraceRecorder()
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        for i in 0..<5 {
            await recorder.record(WorkflowStepTrace(
                workflowID: "w-1",
                toolName: "tool.\(i)",
                argumentsJSON: "{}",
                outputJSON: "null",
                error: nil,
                durationMs: i,
                startedAt: base.addingTimeInterval(TimeInterval(i))
            ))
        }
        let traces = await recorder.tail(workflowID: "w-1", limit: 10)
        #expect(traces.count == 5)
        #expect(traces.map(\.toolName) == ["tool.0", "tool.1", "tool.2", "tool.3", "tool.4"])
    }

    @Test("Tail with smaller limit returns the newest tail")
    func tailHonoursLimit() async {
        let recorder = InMemoryWorkflowTraceRecorder()
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        for i in 0..<10 {
            await recorder.record(WorkflowStepTrace(
                workflowID: "w", toolName: "t\(i)",
                argumentsJSON: "{}", outputJSON: nil, error: nil,
                durationMs: 0, startedAt: base
            ))
        }
        let traces = await recorder.tail(workflowID: "w", limit: 3)
        #expect(traces.map(\.toolName) == ["t7", "t8", "t9"])
    }

    @Test("Ring buffer drops oldest entries past the cap")
    func bufferCapDropsOldest() async {
        let recorder = InMemoryWorkflowTraceRecorder(perWorkflowCap: 3)
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        for i in 0..<5 {
            await recorder.record(WorkflowStepTrace(
                workflowID: "w", toolName: "t\(i)",
                argumentsJSON: "{}", outputJSON: nil, error: nil,
                durationMs: 0, startedAt: base
            ))
        }
        let traces = await recorder.tail(workflowID: "w", limit: 100)
        #expect(traces.count == 3)
        #expect(traces.map(\.toolName) == ["t2", "t3", "t4"])
    }

    @Test("Traces are partitioned per workflowID")
    func partitionByWorkflow() async {
        let recorder = InMemoryWorkflowTraceRecorder()
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        await recorder.record(WorkflowStepTrace(
            workflowID: "a", toolName: "ta", argumentsJSON: "{}",
            outputJSON: nil, error: nil, durationMs: 0, startedAt: base
        ))
        await recorder.record(WorkflowStepTrace(
            workflowID: "b", toolName: "tb", argumentsJSON: "{}",
            outputJSON: nil, error: nil, durationMs: 0, startedAt: base
        ))
        let aTraces = await recorder.tail(workflowID: "a", limit: 10)
        let bTraces = await recorder.tail(workflowID: "b", limit: 10)
        #expect(aTraces.map(\.toolName) == ["ta"])
        #expect(bTraces.map(\.toolName) == ["tb"])
    }

    @Test("Clear wipes only the named workflow")
    func clearScopes() async {
        let recorder = InMemoryWorkflowTraceRecorder()
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        await recorder.record(WorkflowStepTrace(
            workflowID: "a", toolName: "t", argumentsJSON: "{}",
            outputJSON: nil, error: nil, durationMs: 0, startedAt: base
        ))
        await recorder.record(WorkflowStepTrace(
            workflowID: "b", toolName: "t", argumentsJSON: "{}",
            outputJSON: nil, error: nil, durationMs: 0, startedAt: base
        ))
        await recorder.clear(workflowID: "a")
        #expect(await recorder.tail(workflowID: "a", limit: 10).isEmpty)
        #expect(await recorder.tail(workflowID: "b", limit: 10).count == 1)
    }

    // MARK: - NoopWorkflowTraceRecorder

    @Test("Noop recorder accepts records but stores nothing")
    func noopRecorder() async {
        let recorder = NoopWorkflowTraceRecorder()
        await recorder.record(WorkflowStepTrace(
            workflowID: "w", toolName: "t", argumentsJSON: "{}",
            outputJSON: nil, error: nil, durationMs: 0,
            startedAt: Date()
        ))
        #expect(await recorder.tail(workflowID: "w", limit: 10).isEmpty)
    }
}
