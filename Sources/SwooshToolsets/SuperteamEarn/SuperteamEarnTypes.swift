// SwooshToolsets/SuperteamEarn/SuperteamEarnTypes.swift — Wire types — 1.0
//
// Codable models for the Superteam Earn Agent API. Every endpoint's
// request and response is typed here so callers never build raw JSON.

import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - Registration
// ═══════════════════════════════════════════════════════════════════

public struct EarnAgentRegistration: Codable, Sendable {
    public let name: String
    public init(name: String) { self.name = name }
}

public struct EarnAgentCredentials: Codable, Sendable {
    public let apiKey: String
    public let claimCode: String
    public let agentId: String
    public let username: String
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Listings
// ═══════════════════════════════════════════════════════════════════

public enum EarnListingType: String, Codable, Sendable, CaseIterable {
    case bounty, project, hackathon
}

public enum EarnAgentAccess: String, Codable, Sendable {
    case AGENT_ALLOWED, AGENT_ONLY
}

public struct EarnListing: Codable, Sendable, Identifiable {
    public let id: String
    public let slug: String?
    public let title: String?
    public let type: String?
    public let description: String?
    public let deadline: String?
    public let rewardAmount: Double?
    public let token: String?
    public let compensationType: String?
    public let agentAccess: String?
    public let pocId: String?
    public let eligibilityQuestions: [EarnEligibilityQuestion]?
}

public struct EarnEligibilityQuestion: Codable, Sendable {
    public let question: String
    public let order: Int?
    public let type: String?
}

public struct EarnListingsResponse: Codable, Sendable {
    public let listings: [EarnListing]?
    // Some endpoints return a flat array, some wrap in an object.
    // The client normalises both.
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Submissions
// ═══════════════════════════════════════════════════════════════════

public struct EarnEligibilityAnswer: Codable, Sendable {
    public let question: String
    public let answer: String

    public init(question: String, answer: String) {
        self.question = question
        self.answer = answer
    }
}

public struct EarnSubmissionRequest: Codable, Sendable {
    public let listingId: String
    public let link: String?
    public let tweet: String?
    public let otherInfo: String?
    public let eligibilityAnswers: [EarnEligibilityAnswer]?
    public let ask: Double?
    public let telegram: String?

    public init(
        listingId: String,
        link: String? = nil,
        tweet: String? = nil,
        otherInfo: String? = nil,
        eligibilityAnswers: [EarnEligibilityAnswer]? = nil,
        ask: Double? = nil,
        telegram: String? = nil
    ) {
        self.listingId = listingId
        self.link = link
        self.tweet = tweet
        self.otherInfo = otherInfo
        self.eligibilityAnswers = eligibilityAnswers
        self.ask = ask
        self.telegram = telegram
    }
}

public struct EarnSubmissionResponse: Codable, Sendable {
    public let id: String?
    public let listingId: String?
    public let status: String?
    public let link: String?
    public let otherInfo: String?
    public let createdAt: String?
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Comments
// ═══════════════════════════════════════════════════════════════════

public struct EarnComment: Codable, Sendable, Identifiable {
    public let id: String
    public let message: String?
    public let authorId: String?
    public let authorName: String?
    public let createdAt: String?
    public let refType: String?
    public let refId: String?
    public let replyToId: String?
}

public struct EarnCommentRequest: Codable, Sendable {
    public let refType: String
    public let refId: String
    public let message: String
    public let pocId: String?
    public let replyToId: String?
    public let replyToUserId: String?

    public init(
        refType: String,
        refId: String,
        message: String,
        pocId: String? = nil,
        replyToId: String? = nil,
        replyToUserId: String? = nil
    ) {
        self.refType = refType
        self.refId = refId
        self.message = message
        self.pocId = pocId
        self.replyToId = replyToId
        self.replyToUserId = replyToUserId
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Claim
// ═══════════════════════════════════════════════════════════════════

public struct EarnClaimRequest: Codable, Sendable {
    public let claimCode: String
    public init(claimCode: String) { self.claimCode = claimCode }
}

public struct EarnClaimResponse: Codable, Sendable {
    public let success: Bool?
    public let message: String?
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Heartbeat
// ═══════════════════════════════════════════════════════════════════

public enum EarnHeartbeatStatus: String, Codable, Sendable {
    case ok, degraded, blocked
}

public struct EarnHeartbeat: Codable, Sendable {
    public let status: EarnHeartbeatStatus
    public let agentName: String
    public let time: String
    public let version: String
    public let capabilities: [String]
    public let lastAction: String
    public let nextAction: String

    public init(
        status: EarnHeartbeatStatus = .ok,
        agentName: String,
        lastAction: String = "idle",
        nextAction: String = "waiting"
    ) {
        self.status = status
        self.agentName = agentName
        self.time = ISO8601DateFormatter().string(from: Date())
        self.version = "earn-agent-mvp"
        self.capabilities = ["register", "listings", "submit", "claim"]
        self.lastAction = lastAction
        self.nextAction = nextAction
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - API Error
// ═══════════════════════════════════════════════════════════════════

public struct EarnAPIError: Error, Sendable, CustomStringConvertible {
    public let statusCode: Int
    public let message: String

    public var description: String { "Earn API \(statusCode): \(message)" }

    public var isUnauthorized: Bool { statusCode == 401 }
    public var isForbidden: Bool { statusCode == 403 }
    public var isRateLimited: Bool { statusCode == 429 }
    public var isValidation: Bool { statusCode == 400 }
}
