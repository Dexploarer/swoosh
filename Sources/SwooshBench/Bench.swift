// SwooshBench/Bench.swift — Practical agent reliability benchmark
//
// Not research tooling. Reliability tooling.

import Foundation
import SwooshTools

// MARK: - Benchmark metrics

public struct BenchmarkMetrics: Codable, Sendable {
    public var toolCallValidityRate: Double
    public var toolCallRepairRate: Double
    public var permissionViolationRate: Double
    public var memoryPrecision: Double
    public var memoryRecall: Double
    public var workflowCompletionRate: Double
    public var subagentHandoffQuality: Double
    public var costPerCompletedTask: Double
    public var latencyToFirstAction: TimeInterval
    public var localVsRemoteRoutingQuality: Double
    public var replayDeterminism: Double
    public var userApprovalBurden: Double

    public init() {
        toolCallValidityRate = 0
        toolCallRepairRate = 0
        permissionViolationRate = 0
        memoryPrecision = 0
        memoryRecall = 0
        workflowCompletionRate = 0
        subagentHandoffQuality = 0
        costPerCompletedTask = 0
        latencyToFirstAction = 0
        localVsRemoteRoutingQuality = 0
        replayDeterminism = 0
        userApprovalBurden = 0
    }
}

// MARK: - Benchmark scenario

public struct BenchmarkScenario: Codable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let category: BenchmarkCategory
    public let prompt: String
    public let expectedToolCalls: [String]
    public let expectedOutputContains: [String]
    public let maxDuration: TimeInterval
    public let maxCost: Double

    public init(
        id: UUID = UUID(),
        name: String,
        category: BenchmarkCategory,
        prompt: String,
        expectedToolCalls: [String] = [],
        expectedOutputContains: [String] = [],
        maxDuration: TimeInterval = 120,
        maxCost: Double = 1.0
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.prompt = prompt
        self.expectedToolCalls = expectedToolCalls
        self.expectedOutputContains = expectedOutputContains
        self.maxDuration = maxDuration
        self.maxCost = maxCost
    }
}

public enum BenchmarkCategory: String, Codable, Sendable, CaseIterable {
    case swiftRepoMaintenance
    case xcodeDebugging
    case pdfToCalendar
    case mailTriage
    case browserFormWorkflow
    case githubIssueHandling
    case localFileOrganization
    case scheduledDigest
    case multiAgentCodeReview
    case memoryRegression
}

// MARK: - Benchmark result

public struct BenchmarkResult: Codable, Sendable, Identifiable {
    public let id: UUID
    public let scenarioID: UUID
    public let startedAt: Date
    public var completedAt: Date?
    public var passed: Bool
    public var metrics: BenchmarkMetrics
    public var toolCallsMade: [String]
    public var errors: [String]
    public var cost: Double
}

// MARK: - Benchmark suite

public struct BenchmarkSuite: Sendable {
    public let scenarios: [BenchmarkScenario]

    public init(scenarios: [BenchmarkScenario]) {
        self.scenarios = scenarios
    }

    /// Built-in suite covering the core benchmark categories.
    public static let standard = BenchmarkSuite(scenarios: [
        BenchmarkScenario(
            name: "Swift Package Audit",
            category: .swiftRepoMaintenance,
            prompt: "Audit this Swift package. Check for unused dependencies, missing tests, and deprecated APIs.",
            expectedToolCalls: ["file.read", "shell.run"]
        ),
        BenchmarkScenario(
            name: "Xcode Build Failure Triage",
            category: .xcodeDebugging,
            prompt: "The Xcode build failed with 3 errors. Read the build log, identify the root causes, and suggest fixes.",
            expectedToolCalls: ["file.read"]
        ),
        BenchmarkScenario(
            name: "PDF Deadline Extraction",
            category: .pdfToCalendar,
            prompt: "Read the attached PDF, extract all deadlines and dates, and create calendar events.",
            expectedToolCalls: ["file.read", "calendar.create"]
        ),
        BenchmarkScenario(
            name: "Mail Thread Drafting",
            category: .mailTriage,
            prompt: "Review these 5 email threads and draft concise replies. Do not send.",
            expectedToolCalls: ["mail.read", "mail.draft"]
        ),
        BenchmarkScenario(
            name: "GitHub Issue Organization",
            category: .githubIssueHandling,
            prompt: "List open issues, label bugs vs features, create a priority board.",
            expectedToolCalls: ["mcp.github.list_issues"]
        ),
        BenchmarkScenario(
            name: "Memory Regression",
            category: .memoryRegression,
            prompt: "Verify that previously stored user preferences are correctly recalled and applied.",
            expectedToolCalls: ["memory.recall"]
        ),
    ])
}
