// Tests/SwooshFlowTests/TracingWorkflowStepExecutorTests.swift — 0.5E
//
// Confirms the wrapper:
//   • Delegates to the inner `WorkflowStepExecuting` and returns its result unchanged.
//   • Emits exactly one trace per call (success and failure).
//   • Records the step duration via the injectable clock.
//   • Rethrows inner errors after recording.

import Foundation
import Testing
import SwooshTools
@testable import SwooshFlow

@Suite("TracingWorkflowStepExecutor")
struct TracingWorkflowStepExecutorTests {

    private func makeContext() -> ToolContext {
        ToolContext(sessionID: "s1")
    }

    // MARK: - Pass-through + record

    @Test("Success records one trace and returns the inner result unchanged")
    func successDelegatesAndRecords() async throws {
        let inner = StaticExecutor.success(
            output: .object(["hits": .int(0)])
        )
        let recorder = InMemoryWorkflowTraceRecorder()
        let executor = TracingWorkflowStepExecutor(
            inner: inner, recorder: recorder, workflowID: "wf-test"
        )

        let result = try await executor.executeWorkflowStep(
            toolName: "memory.search",
            arguments: .object(["q": .string("hello")]),
            context: makeContext()
        )
        #expect(result.toolName == "memory.search")
        #expect(result.status == .succeeded)

        let traces = await recorder.tail(workflowID: "wf-test", limit: 10)
        #expect(traces.count == 1)
        #expect(traces.first?.toolName == "memory.search")
        #expect(traces.first?.outputJSON?.contains("hits") == true)
        #expect(traces.first?.error == nil)
    }

    @Test("Inner throw records a failure trace and rethrows")
    func errorRecordsTraceAndRethrows() async {
        let inner = StaticExecutor.throwing(message: "boom")
        let recorder = InMemoryWorkflowTraceRecorder()
        let executor = TracingWorkflowStepExecutor(
            inner: inner, recorder: recorder, workflowID: "wf-err"
        )

        do {
            _ = try await executor.executeWorkflowStep(
                toolName: "memory.search",
                arguments: .object([:]),
                context: makeContext()
            )
            Issue.record("expected throw")
        } catch {
            // expected
        }

        let traces = await recorder.tail(workflowID: "wf-err", limit: 10)
        #expect(traces.count == 1)
        #expect(traces.first?.error != nil)
        #expect(traces.first?.outputJSON == nil)
    }

    @Test("Per-call clock determines startedAt and durationMs")
    func durationFromClock() async throws {
        let inner = StaticExecutor.success(output: .null)
        let recorder = InMemoryWorkflowTraceRecorder()
        let ticks = TickClock(values: [
            Date(timeIntervalSince1970: 1_800_000_000),
            Date(timeIntervalSince1970: 1_800_000_002),
        ])
        let executor = TracingWorkflowStepExecutor(
            inner: inner, recorder: recorder, workflowID: "wf-clock",
            clock: ticks.next
        )

        _ = try await executor.executeWorkflowStep(
            toolName: "x", arguments: .null, context: makeContext()
        )
        let trace = await recorder.tail(workflowID: "wf-clock", limit: 1).first
        #expect(trace?.startedAt == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(trace?.durationMs == 2000)
    }

    // MARK: - Many calls

    @Test("Multiple sequential calls accumulate one trace each, in order")
    func multipleCallsAccumulate() async throws {
        let inner = StaticExecutor.success(output: .string("ok"))
        let recorder = InMemoryWorkflowTraceRecorder()
        let executor = TracingWorkflowStepExecutor(
            inner: inner, recorder: recorder, workflowID: "wf-multi"
        )

        for i in 0..<4 {
            _ = try await executor.executeWorkflowStep(
                toolName: "tool.\(i)",
                arguments: .null,
                context: makeContext()
            )
        }
        let traces = await recorder.tail(workflowID: "wf-multi", limit: 10)
        #expect(traces.map(\.toolName) == ["tool.0", "tool.1", "tool.2", "tool.3"])
    }
}

// MARK: - Test doubles

private struct StaticExecutor: WorkflowStepExecuting {
    enum Mode: Sendable {
        case success(output: JSONValue)
        case throwing(message: String)
    }
    let mode: Mode

    static func success(output: JSONValue) -> StaticExecutor {
        StaticExecutor(mode: .success(output: output))
    }
    static func throwing(message: String) -> StaticExecutor {
        StaticExecutor(mode: .throwing(message: message))
    }

    func executeWorkflowStep(
        toolName: String,
        arguments: JSONValue,
        context: ToolContext
    ) async throws -> ToolExecutionResult {
        switch mode {
        case .success(let output):
            return ToolExecutionResult(
                requestID: "req-1",
                toolName: toolName,
                status: .succeeded,
                output: output
            )
        case .throwing(let message):
            throw StaticExecutorError.boom(message)
        }
    }
}

private enum StaticExecutorError: Error {
    case boom(String)
}

/// Sequenced clock — each `next()` call advances to the next stored
/// date, so we can pin elapsed-ms in tests deterministically.
private final class TickClock: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Date]
    private var idx = 0
    init(values: [Date]) { self.values = values }
    @Sendable func next() -> Date {
        lock.lock(); defer { lock.unlock() }
        defer { idx = min(idx + 1, values.count - 1) }
        return values[idx]
    }
}
