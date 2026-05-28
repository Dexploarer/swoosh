// SwooshToolsets/WebSearchTools.swift — 0.1A Web search tool (Tavily)
//
// A typed `web.search` tool behind the existing `.webSearch` permission
// (the ToolRegistry enforces it — no inline firewall check here). The
// search backend is injectable so the tool is testable with a mock and
// the live path stays a thin Tavily HTTP call. The API key is resolved
// from SwooshSecrets via the `tavily.api_key` ref — never inlined.
//
// Ports detour's plugin-web-search capability (Swoosh had the
// `.webSearch` permission case but no tool behind it).

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - I/O types
// ═══════════════════════════════════════════════════════════════════

public struct WebSearchResult: Codable, Sendable, Equatable {
    public let title: String
    public let url: String
    public let snippet: String
    public init(title: String, url: String, snippet: String) {
        self.title = title; self.url = url; self.snippet = snippet
    }
}

public struct WebSearchInput: Codable, Sendable {
    public let query: String
    public let maxResults: Int?
    public init(query: String, maxResults: Int? = nil) {
        self.query = query; self.maxResults = maxResults
    }
}

public struct WebSearchOutput: Codable, Sendable {
    public let results: [WebSearchResult]
    public let provider: String
    public init(results: [WebSearchResult], provider: String) {
        self.results = results; self.provider = provider
    }
}

public enum WebSearchError: Error, LocalizedError, Sendable {
    case missingAPIKey
    case emptyQuery
    case backendFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Web search API key not found. Run: swoosh provider auth tavily --api-key"
        case .emptyQuery:
            return "Web search query must not be empty."
        case .backendFailed(let m):
            return "Web search failed: \(m)"
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Backend
// ═══════════════════════════════════════════════════════════════════

/// Pluggable search backend. The live default is Tavily; tests inject a
/// deterministic mock so the tool's contract is exercised without network.
public protocol WebSearchBackend: Sendable {
    func search(query: String, maxResults: Int, apiKey: String) async throws -> [WebSearchResult]
}

/// Tavily Search API backend (api.tavily.com/search). Bearer-auth.
public struct TavilyWebSearchBackend: WebSearchBackend {
    private let session: URLSession
    private let endpoint: URL

    public init(session: URLSession = .shared,
                endpoint: URL = URL(string: "https://api.tavily.com/search")!) {
        self.session = session; self.endpoint = endpoint
    }

    public func search(query: String, maxResults: Int, apiKey: String) async throws -> [WebSearchResult] {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "query": query,
            "max_results": maxResults,
            "search_depth": "basic",
        ])

        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw WebSearchError.backendFailed("HTTP \(http.statusCode): \(body.prefix(200))")
        }
        return Self.parse(data)
    }

    static func parse(_ data: Data) -> [WebSearchResult] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = json["results"] as? [[String: Any]] else {
            return []
        }
        return rows.map { row in
            WebSearchResult(
                title: (row["title"] as? String) ?? "",
                url: (row["url"] as? String) ?? "",
                snippet: (row["content"] as? String) ?? ""
            )
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Tool
// ═══════════════════════════════════════════════════════════════════

public struct WebSearchTool: SwooshTool {
    public typealias Input = WebSearchInput
    public typealias Output = WebSearchOutput

    public static let name: ToolName = "web.search"
    public static let displayName = "Web Search"
    public static let description = "Search the web and return ranked title/url/snippet results."
    public static let permission = SwooshPermission.webSearch
    public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.web

    /// Cap so the model can't request an unbounded page; mirrors Tavily's
    /// own practical ceiling.
    static let maxAllowedResults = 10
    static let defaultResults = 5
    static let secretRef = "tavily.api_key"

    private let dependencies: ToolDependencies
    private let backend: any WebSearchBackend

    public init(dependencies: ToolDependencies, backend: any WebSearchBackend = TavilyWebSearchBackend()) {
        self.dependencies = dependencies
        self.backend = backend
    }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let query = input.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw WebSearchError.emptyQuery }

        let apiKey: String
        do {
            apiKey = try await dependencies.secrets.resolve(ref: Self.secretRef)
        } catch {
            throw WebSearchError.missingAPIKey
        }
        guard !apiKey.isEmpty else { throw WebSearchError.missingAPIKey }

        let requested = input.maxResults ?? Self.defaultResults
        let clamped = max(1, min(requested, Self.maxAllowedResults))
        let results = try await backend.search(query: query, maxResults: clamped, apiKey: apiKey)
        return WebSearchOutput(results: results, provider: "tavily")
    }
}
