// SwooshFlow/Workflow.swift — "Make this repeatable"
//
// Skills compiled into testable, replayable, inspectable workflow graphs.
// The killer loop: do once → extract → test → schedule → improve → version.

import Foundation
import SwooshTools

// MARK: - Workflow definition

public struct Workflow: Codable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var description: String
    public var version: String
    public var steps: [WorkflowStep]
    public var requiredTools: Set<String>
    public var requiredPermissions: Set<SwooshPermission>
    public var trigger: WorkflowTriggerLegacy?
    public var modelRoute: ModelRoute
    public var testFixture: WorkflowTestFixture?
    public var failureRules: [FailureRule]
    public var memoryDependencies: [String]
    public var createdAt: Date
    public var lastRunAt: Date?
    public var runCount: Int

    public init(
        id: UUID = UUID(),
        name: String,
        description: String,
        version: String = "1.0.0",
        steps: [WorkflowStep] = [],
        requiredTools: Set<String> = [],
        requiredPermissions: Set<SwooshPermission> = [],
        trigger: WorkflowTriggerLegacy? = nil,
        modelRoute: ModelRoute = .auto,
        testFixture: WorkflowTestFixture? = nil,
        failureRules: [FailureRule] = [],
        memoryDependencies: [String] = [],
        createdAt: Date = Date(),
        lastRunAt: Date? = nil,
        runCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.version = version
        self.steps = steps
        self.requiredTools = requiredTools
        self.requiredPermissions = requiredPermissions
        self.trigger = trigger
        self.modelRoute = modelRoute
        self.testFixture = testFixture
        self.failureRules = failureRules
        self.memoryDependencies = memoryDependencies
        self.createdAt = createdAt
        self.lastRunAt = lastRunAt
        self.runCount = runCount
    }
}

// MARK: - Workflow steps

public struct WorkflowStep: Codable, Sendable, Identifiable {
    public let id: UUID
    public var label: String
    public var action: WorkflowAction
    public var dependsOn: [UUID]

    public init(id: UUID = UUID(), label: String, action: WorkflowAction, dependsOn: [UUID] = []) {
        self.id = id
        self.label = label
        self.action = action
        self.dependsOn = dependsOn
    }
}

public enum WorkflowAction: Codable, Sendable {
    case toolCall(name: String, arguments: JSONValue)
    case agentPrompt(prompt: String, modelRoute: ModelRoute?)
    case subworkflow(workflowID: UUID)
    case humanApproval(message: String)
    case conditional(condition: String, ifTrue: UUID, ifFalse: UUID)
}

// MARK: - Triggers (legacy local diagnostic — replaced by WorkflowTrigger in WorkflowTriggerTypes.swift)

public enum WorkflowTriggerLegacy: Codable, Sendable {
    // Time-based
    case cron(expression: String)
    case naturalLanguage(schedule: String)
    case everyWeekday(at: String)

    // Event-based
    case fileChanged(path: String)
    case calendarEventStarts(minutesBefore: Int)
    case focusModeChanged(to: String)
    case appLaunched(bundleID: String)
    case repoChanged(path: String)
    case emailReceived(filter: String)
    case wifiChanged(to: String)
    case batteryThreshold(percent: Int)
    case shortcutInvoked(name: String)
    case webhookReceived(path: String)
}

// ModelRoute is defined in SwooshTools/Types.swift


// MARK: - Test fixtures

public struct WorkflowTestFixture: Codable, Sendable {
    public var inputMock: JSONValue
    public var expectedOutputContains: [String]
    public var expectedToolCalls: [String]
    public var maxDuration: TimeInterval

    public init(
        inputMock: JSONValue = .null,
        expectedOutputContains: [String] = [],
        expectedToolCalls: [String] = [],
        maxDuration: TimeInterval = 300
    ) {
        self.inputMock = inputMock
        self.expectedOutputContains = expectedOutputContains
        self.expectedToolCalls = expectedToolCalls
        self.maxDuration = maxDuration
    }
}

// MARK: - Failure rules

public struct FailureRule: Codable, Sendable {
    public var condition: FailureCondition
    public var action: FailureAction

    public init(condition: FailureCondition, action: FailureAction) {
        self.condition = condition
        self.action = action
    }
}

public enum FailureCondition: Codable, Sendable {
    case toolError(name: String)
    case timeout
    case modelError
    case permissionDenied
    case anyError
}

public enum FailureAction: Codable, Sendable {
    case retry(maxAttempts: Int)
    case retryWithModel(ModelRoute)
    case skipStep
    case abort
    case notifyUser(message: String)
    case fallbackWorkflow(id: UUID)
}

// MARK: - Workflow execution record (for replay)

public struct WorkflowRun: Codable, Sendable, Identifiable {
    public let id: UUID
    public let workflowID: UUID
    public let startedAt: Date
    public var completedAt: Date?
    public var status: WorkflowRunStatus
    public var stepResults: [StepResult]
    public var totalCost: Double

    public init(id: UUID = UUID(), workflowID: UUID, startedAt: Date = Date()) {
        self.id = id
        self.workflowID = workflowID
        self.startedAt = startedAt
        self.status = .running
        self.stepResults = []
        self.totalCost = 0
    }
}

public enum WorkflowRunStatus: String, Codable, Sendable {
    case running
    case succeeded
    case failed
    case aborted
    case waitingForApproval
}

public struct StepResult: Codable, Sendable {
    public let stepID: UUID
    public let startedAt: Date
    public var completedAt: Date?
    public var output: String?
    public var error: String?
    public var toolCalls: [ToolCall]
}

// MARK: - Workflow compiler

/// Given a successful agent session transcript, extract a reusable Workflow.
/// This is the "Make this repeatable" feature.
public struct WorkflowCompiler {
    public init() {}

    public func compile(
        name: String,
        description: String,
        transcript: [ChatMessage],
        toolCalls: [ToolCall]
    ) -> Workflow {
        // Extract the tool calls as workflow steps
        var steps: [WorkflowStep] = []
        var requiredTools: Set<String> = []
        var previousStepID: UUID? = nil

        for call in toolCalls {
            let step = WorkflowStep(
                label: call.name,
                action: .toolCall(name: call.name, arguments: call.arguments),
                dependsOn: previousStepID.map { [$0] } ?? []
            )
            steps.append(step)
            requiredTools.insert(call.name)
            previousStepID = step.id
        }

        return Workflow(
            name: name,
            description: description,
            steps: steps,
            requiredTools: requiredTools,
            failureRules: [
                FailureRule(condition: .anyError, action: .retry(maxAttempts: 2)),
                FailureRule(condition: .timeout, action: .notifyUser(message: "Workflow '\(name)' timed out."))
            ]
        )
    }
}
