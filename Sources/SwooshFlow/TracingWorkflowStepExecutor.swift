// SwooshFlow/TracingWorkflowStepExecutor.swift — 0.5E Trace-emitting workflow executor
//
// Wraps any inner `SwooshTools.WorkflowStepExecuting` (typically
// `RegistryWorkflowStepExecutor`) and emits a `WorkflowStepTrace` per
// step to a `WorkflowTraceRecording`. The daemon and CLI inject this
// wrapper so runtime `workflow.run` calls leave a queryable, replayable
// trail — engineering rule #4.
//
// Safe to wrap: errors from the inner executor are re-thrown after the
// trace has been recorded, so a step failure never silently loses its
// audit entry.

import Foundation
import SwooshTools

public struct TracingWorkflowStepExecutor: WorkflowStepExecuting, Sendable {
    public let inner: any WorkflowStepExecuting
    public let recorder: any WorkflowTraceRecording
    public let workflowID: String
    public let clock: @Sendable () -> Date

    public init(
        inner: any WorkflowStepExecuting,
        recorder: any WorkflowTraceRecording,
        workflowID: String,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.inner = inner
        self.recorder = recorder
        self.workflowID = workflowID
        self.clock = clock
    }

    public func executeWorkflowStep(
        toolName: String,
        arguments: JSONValue,
        context: ToolContext
    ) async throws -> ToolExecutionResult {
        let startedAt = clock()
        let argsJSON = (try? encode(arguments)) ?? "{}"

        do {
            let result = try await inner.executeWorkflowStep(
                toolName: toolName,
                arguments: arguments,
                context: context
            )
            let outputJSON = result.output.flatMap { (try? encode($0)) } ?? "null"
            let elapsedMs = Int(clock().timeIntervalSince(startedAt) * 1000)
            await recorder.record(WorkflowStepTrace(
                workflowID: workflowID,
                toolName: toolName,
                argumentsJSON: argsJSON,
                outputJSON: outputJSON,
                error: result.errorMessage,
                durationMs: elapsedMs,
                startedAt: startedAt
            ))
            return result
        } catch {
            let elapsedMs = Int(clock().timeIntervalSince(startedAt) * 1000)
            await recorder.record(WorkflowStepTrace(
                workflowID: workflowID,
                toolName: toolName,
                argumentsJSON: argsJSON,
                outputJSON: nil,
                error: String(describing: error),
                durationMs: elapsedMs,
                startedAt: startedAt
            ))
            throw error
        }
    }

    private func encode(_ value: JSONValue) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8) ?? "null"
    }
}
