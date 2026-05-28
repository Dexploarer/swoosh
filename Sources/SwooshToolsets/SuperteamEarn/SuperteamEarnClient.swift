// SwooshToolsets/SuperteamEarn/SuperteamEarnClient.swift — HTTP client — 1.0
//
// Typed async actor wrapping every Superteam Earn Agent API endpoint.
// No raw JSON anywhere — callers get Codable structs in, Codable structs
// out. URLSession-based, zero external dependencies.
//
// Usage:
//   let client = SuperteamEarnClient(
//       baseURL: URL(string: "https://earn.superteam.fun")!,
//       apiKey: "sk_..."
//   )
//   let listings = try await client.liveListings(take: 20)
//   try await client.submitListing(.init(listingId: "...", link: "..."))

import Foundation

public actor SuperteamEarnClient {

    // ── Configuration ────────────────────────────────────────────────

    public let baseURL: URL
    private var apiKey: String?
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Track last action for heartbeat generation.
    private var lastActionDescription: String = "initialized"
    private var agentName: String = "swoosh-earn-agent"

    public init(
        baseURL: URL = URL(string: "https://earn.superteam.fun")!,
        apiKey: String? = nil
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)

        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    /// Update the API key after registration.
    public func setAPIKey(_ key: String) {
        self.apiKey = key
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Registration
    // ═══════════════════════════════════════════════════════════════════

    /// Register a new agent. Returns credentials including the API key
    /// and claim code. The API key is automatically stored for subsequent
    /// requests.
    public func register(name: String) async throws -> EarnAgentCredentials {
        let body = EarnAgentRegistration(name: name)
        let creds: EarnAgentCredentials = try await post(
            path: "/api/agents",
            body: body,
            authenticated: false
        )
        self.apiKey = creds.apiKey
        self.agentName = name
        lastActionDescription = "registered as \(name)"
        return creds
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Listings
    // ═══════════════════════════════════════════════════════════════════

    /// Fetch live agent-eligible listings.
    public func liveListings(
        take: Int = 20,
        type: EarnListingType? = nil,
        deadline: String? = nil
    ) async throws -> [EarnListing] {
        var query = "take=\(take)"
        if let type { query += "&type=\(type.rawValue)" }
        if let deadline { query += "&deadline=\(deadline)" }

        let listings: [EarnListing] = try await get(
            path: "/api/agents/listings/live?\(query)"
        )
        lastActionDescription = "fetched \(listings.count) live listings"
        return listings
    }

    /// Fetch details for a specific listing by slug.
    public func listingDetails(slug: String) async throws -> EarnListing {
        let listing: EarnListing = try await get(
            path: "/api/agents/listings/details/\(slug)"
        )
        lastActionDescription = "fetched details for \(slug)"
        return listing
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Submissions
    // ═══════════════════════════════════════════════════════════════════

    /// Submit work to a listing.
    public func createSubmission(
        _ submission: EarnSubmissionRequest
    ) async throws -> EarnSubmissionResponse {
        let response: EarnSubmissionResponse = try await post(
            path: "/api/agents/submissions/create",
            body: submission
        )
        lastActionDescription = "submitted to listing \(submission.listingId)"
        return response
    }

    /// Edit an existing submission.
    public func updateSubmission(
        _ submission: EarnSubmissionRequest
    ) async throws -> EarnSubmissionResponse {
        let response: EarnSubmissionResponse = try await post(
            path: "/api/agents/submissions/update",
            body: submission
        )
        lastActionDescription = "updated submission for listing \(submission.listingId)"
        return response
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Comments
    // ═══════════════════════════════════════════════════════════════════

    /// Fetch comments for a listing.
    public func comments(
        listingId: String,
        skip: Int = 0,
        take: Int = 20
    ) async throws -> [EarnComment] {
        let comments: [EarnComment] = try await get(
            path: "/api/agents/comments/\(listingId)?skip=\(skip)&take=\(take)"
        )
        lastActionDescription = "fetched \(comments.count) comments on \(listingId)"
        return comments
    }

    /// Post a new comment or reply.
    public func postComment(
        _ comment: EarnCommentRequest
    ) async throws -> EarnComment {
        let response: EarnComment = try await post(
            path: "/api/agents/comments/create",
            body: comment
        )
        lastActionDescription = "posted comment on \(comment.refId)"
        return response
    }

    /// Convenience: reply to a specific comment.
    public func replyToComment(
        listingId: String,
        message: String,
        replyToId: String,
        replyToUserId: String,
        pocId: String? = nil,
        refType: String = "BOUNTY"
    ) async throws -> EarnComment {
        try await postComment(.init(
            refType: refType,
            refId: listingId,
            message: message,
            pocId: pocId,
            replyToId: replyToId,
            replyToUserId: replyToUserId
        ))
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Claim
    // ═══════════════════════════════════════════════════════════════════

    /// Claim an agent for payout (called by a human with their auth token).
    public func claim(
        claimCode: String,
        humanToken: String
    ) async throws -> EarnClaimResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/agents/claim"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(humanToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(EarnClaimRequest(claimCode: claimCode))

        let (data, httpResponse) = try await session.data(for: request)
        try checkResponse(httpResponse, data: data)
        lastActionDescription = "claimed agent with code \(claimCode)"
        return try decoder.decode(EarnClaimResponse.self, from: data)
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Heartbeat
    // ═══════════════════════════════════════════════════════════════════

    /// Generate a heartbeat payload reflecting current client state.
    public func heartbeat(
        status: EarnHeartbeatStatus = .ok,
        nextAction: String = "waiting"
    ) -> EarnHeartbeat {
        EarnHeartbeat(
            status: status,
            agentName: agentName,
            lastAction: lastActionDescription,
            nextAction: nextAction
        )
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Convenience builders
    // ═══════════════════════════════════════════════════════════════════

    /// Build a submission request with eligibility answers pre-filled
    /// from the listing's questions.
    public func buildSubmission(
        listing: EarnListing,
        link: String? = nil,
        otherInfo: String? = nil,
        answers: [String: String] = [:],
        ask: Double? = nil,
        telegram: String? = nil
    ) -> EarnSubmissionRequest {
        let eligibility = listing.eligibilityQuestions?.map { q in
            EarnEligibilityAnswer(
                question: q.question,
                answer: answers[q.question] ?? ""
            )
        }
        return EarnSubmissionRequest(
            listingId: listing.id,
            link: link,
            otherInfo: otherInfo,
            eligibilityAnswers: eligibility,
            ask: ask,
            telegram: telegram
        )
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - HTTP internals
    // ═══════════════════════════════════════════════════════════════════

    private func get<T: Decodable>(path: String) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "GET"
        addAuth(&request)

        let (data, httpResponse) = try await session.data(for: request)
        try checkResponse(httpResponse, data: data)
        return try decoder.decode(T.self, from: data)
    }

    private func post<B: Encodable, T: Decodable>(
        path: String,
        body: B,
        authenticated: Bool = true
    ) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated { addAuth(&request) }
        request.httpBody = try encoder.encode(body)

        let (data, httpResponse) = try await session.data(for: request)
        try checkResponse(httpResponse, data: data)
        return try decoder.decode(T.self, from: data)
    }

    private func addAuth(_ request: inout URLRequest) {
        guard let apiKey else { return }
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }

    private func checkResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw EarnAPIError(statusCode: 0, message: "Non-HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unknown error"
            throw EarnAPIError(statusCode: http.statusCode, message: body)
        }
    }
}
