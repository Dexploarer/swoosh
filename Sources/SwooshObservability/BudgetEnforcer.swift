// SwooshObservability/BudgetEnforcer.swift — Hard/soft budget limits
//
// Hermes-inspired budget enforcement. Prevents runaway token/cost
// consumption with configurable hard limits and soft warnings.

import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - Budget policy
// ═══════════════════════════════════════════════════════════════════

/// Budget limits for a session, worker, or agent.
public struct BudgetPolicy: Codable, Sendable {
    public var maxTokensPerSession: Int?
    public var maxTokensPerHour: Int?
    public var maxCostPerSession: Double?
    public var maxCostPerHour: Double?
    public var maxCostPerDay: Double?
    public var maxTurns: Int?
    public var maxToolCalls: Int?
    public var maxWallClockSeconds: Int?
    public var warnAtPercent: Double          // Emit warning at this % of limit

    public init(
        maxTokensPerSession: Int? = nil,
        maxTokensPerHour: Int? = nil,
        maxCostPerSession: Double? = nil,
        maxCostPerHour: Double? = nil,
        maxCostPerDay: Double? = nil,
        maxTurns: Int? = nil,
        maxToolCalls: Int? = nil,
        maxWallClockSeconds: Int? = nil,
        warnAtPercent: Double = 0.80
    ) {
        self.maxTokensPerSession = maxTokensPerSession
        self.maxTokensPerHour = maxTokensPerHour
        self.maxCostPerSession = maxCostPerSession
        self.maxCostPerHour = maxCostPerHour
        self.maxCostPerDay = maxCostPerDay
        self.maxTurns = maxTurns
        self.maxToolCalls = maxToolCalls
        self.maxWallClockSeconds = maxWallClockSeconds
        self.warnAtPercent = warnAtPercent
    }

    /// Reasonable defaults for interactive chat.
    public static let interactive = BudgetPolicy(
        maxTokensPerSession: 500_000,
        maxCostPerSession: 5.00,
        maxCostPerDay: 25.00,
        maxTurns: 100,
        maxToolCalls: 200
    )

    /// Constrained budget for automated workers.
    public static let worker = BudgetPolicy(
        maxTokensPerSession: 100_000,
        maxCostPerSession: 1.00,
        maxTurns: 20,
        maxToolCalls: 50,
        maxWallClockSeconds: 600
    )

    /// Generous budget for long-running workflows.
    public static let workflow = BudgetPolicy(
        maxTokensPerSession: 2_000_000,
        maxCostPerDay: 50.00,
        maxTurns: 500,
        maxToolCalls: 1000,
        maxWallClockSeconds: 7200
    )

    /// No limits (for admin/testing).
    public static let unlimited = BudgetPolicy()
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Budget check result
// ═══════════════════════════════════════════════════════════════════

public enum BudgetCheckResult: Sendable {
    case ok
    case warning(String)                     // Approaching limit
    case exceeded(String)                    // Hard limit hit
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Budget enforcer
// ═══════════════════════════════════════════════════════════════════

/// Enforces budget limits for a session or worker.
public actor BudgetEnforcer {
    private let policy: BudgetPolicy
    private var tokenCount: Int = 0
    private var costUSD: Double = 0
    private var turnCount: Int = 0
    private var toolCallCount: Int = 0
    private let startTime: Date

    public init(policy: BudgetPolicy) {
        self.policy = policy
        self.startTime = Date()
    }

    /// Record tokens consumed.
    public func recordTokens(_ count: Int) {
        tokenCount += count
    }

    /// Record cost.
    public func recordCost(_ amount: Double) {
        costUSD += amount
    }

    /// Record a turn.
    public func recordTurn() {
        turnCount += 1
    }

    /// Record a tool call.
    public func recordToolCall() {
        toolCallCount += 1
    }

    /// Check all budget limits. Returns the most severe violation.
    public func check() -> BudgetCheckResult {
        // Token limits
        if let max = policy.maxTokensPerSession {
            if tokenCount >= max { return .exceeded("Token limit exceeded: \(tokenCount)/\(max)") }
            if Double(tokenCount) / Double(max) >= policy.warnAtPercent {
                return .warning("Token budget \(Int(Double(tokenCount) / Double(max) * 100))% consumed")
            }
        }

        // Cost limits
        if let max = policy.maxCostPerSession {
            if costUSD >= max { return .exceeded("Cost limit exceeded: $\(String(format: "%.2f", costUSD))/$\(String(format: "%.2f", max))") }
            if costUSD / max >= policy.warnAtPercent {
                return .warning("Cost budget \(Int(costUSD / max * 100))% consumed")
            }
        }

        // Turn limits
        if let max = policy.maxTurns {
            if turnCount >= max { return .exceeded("Turn limit exceeded: \(turnCount)/\(max)") }
            if Double(turnCount) / Double(max) >= policy.warnAtPercent {
                return .warning("Turn budget \(Int(Double(turnCount) / Double(max) * 100))% consumed")
            }
        }

        // Tool call limits
        if let max = policy.maxToolCalls {
            if toolCallCount >= max { return .exceeded("Tool call limit exceeded: \(toolCallCount)/\(max)") }
        }

        // Wall clock limits
        if let max = policy.maxWallClockSeconds {
            let elapsed = Int(Date().timeIntervalSince(startTime))
            if elapsed >= max { return .exceeded("Wall clock limit exceeded: \(elapsed)s/\(max)s") }
            if Double(elapsed) / Double(max) >= policy.warnAtPercent {
                return .warning("Wall clock \(Int(Double(elapsed) / Double(max) * 100))% consumed")
            }
        }

        return .ok
    }

    /// Current usage snapshot.
    public func snapshot() -> BudgetSnapshot {
        BudgetSnapshot(
            tokenCount: tokenCount,
            costUSD: costUSD,
            turnCount: turnCount,
            toolCallCount: toolCallCount,
            elapsedSeconds: Int(Date().timeIntervalSince(startTime)),
            policy: policy
        )
    }
}

public struct BudgetSnapshot: Sendable {
    public let tokenCount: Int
    public let costUSD: Double
    public let turnCount: Int
    public let toolCallCount: Int
    public let elapsedSeconds: Int
    public let policy: BudgetPolicy
}
