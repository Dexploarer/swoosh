// Tests/SwooshToolsetsTests/WebSearchToolsTests.swift — 0.1A
//
// Integration tests for the web.search tool: result mapping, max-results
// clamping, missing-key + empty-query error paths, and the Tavily JSON
// parser — all with an injected backend / secret resolver so nothing
// touches the network. Plus a live smoke test gated on TAVILY_API_KEY,
// and a registration check that the tool lands in the registry.

import Testing
import Foundation
@testable import SwooshToolsets
@testable import SwooshTools
@testable import SwooshFirewall
@testable import SwooshFiles
@testable import SwooshProcess

// MARK: - Test doubles

private struct StubSecretResolver: SecretResolving {
    let key: String?
    func resolve(ref: String) async throws -> String {
        guard ref == WebSearchTool.secretRef, let key else {
            throw ToolError.executionFailed("no secret for \(ref)")
        }
        return key
    }
}

private struct RecordingBackend: WebSearchBackend {
    let results: [WebSearchResult]
    let recorder: Recorder

    final class Recorder: @unchecked Sendable {
        var lastQuery: String = ""
        var lastMax: Int = -1
        var lastKey: String = ""
    }

    func search(query: String, maxResults: Int, apiKey: String) async throws -> [WebSearchResult] {
        recorder.lastQuery = query
        recorder.lastMax = maxResults
        recorder.lastKey = apiKey
        return results
    }
}

private func makeDeps(secrets: any SecretResolving) -> ToolDependencies {
    ToolDependencies(
        firewall: SwooshFirewallActor(granted: Set(SwooshPermission.allCases)),
        audit: SwooshAuditLog(),
        approvals: InMemoryApprovalRequester(autoApprove: true),
        fileAccess: SafeFileAccessor(rootStore: InMemoryRootStore()),
        processRunner: StreamingProcessRunner(),
        secrets: secrets
    )
}

private let ctx = ToolContext(sessionID: "web-search-test")

// MARK: - Tests

@Suite("WebSearchTool")
struct WebSearchToolTests {

    @Test("Maps backend results and reports provider")
    func mapsResults() async throws {
        let backend = RecordingBackend(
            results: [
                WebSearchResult(title: "Swift", url: "https://swift.org", snippet: "language"),
                WebSearchResult(title: "Apple", url: "https://apple.com", snippet: "company"),
            ],
            recorder: .init()
        )
        let tool = WebSearchTool(dependencies: makeDeps(secrets: StubSecretResolver(key: "tvly-x")),
                                 backend: backend)
        let out = try await tool.call(WebSearchInput(query: "swift", maxResults: 2), context: ctx)
        #expect(out.results.count == 2)
        #expect(out.results.first?.url == "https://swift.org")
        #expect(out.provider == "tavily")
        #expect(backend.recorder.lastKey == "tvly-x")
        #expect(backend.recorder.lastQuery == "swift")
    }

    @Test("Clamps max results into [1, 10]")
    func clamps() async throws {
        let backend = RecordingBackend(results: [], recorder: .init())
        let tool = WebSearchTool(dependencies: makeDeps(secrets: StubSecretResolver(key: "k")),
                                 backend: backend)
        _ = try await tool.call(WebSearchInput(query: "q", maxResults: 999), context: ctx)
        #expect(backend.recorder.lastMax == WebSearchTool.maxAllowedResults)
        _ = try await tool.call(WebSearchInput(query: "q", maxResults: 0), context: ctx)
        #expect(backend.recorder.lastMax == 1)
    }

    @Test("Defaults max results when omitted")
    func defaults() async throws {
        let backend = RecordingBackend(results: [], recorder: .init())
        let tool = WebSearchTool(dependencies: makeDeps(secrets: StubSecretResolver(key: "k")),
                                 backend: backend)
        _ = try await tool.call(WebSearchInput(query: "q"), context: ctx)
        #expect(backend.recorder.lastMax == WebSearchTool.defaultResults)
    }

    @Test("Missing API key → missingAPIKey")
    func missingKey() async {
        let tool = WebSearchTool(dependencies: makeDeps(secrets: StubSecretResolver(key: nil)),
                                 backend: RecordingBackend(results: [], recorder: .init()))
        do {
            _ = try await tool.call(WebSearchInput(query: "q"), context: ctx)
            Issue.record("Should throw")
        } catch WebSearchError.missingAPIKey {
        } catch { Issue.record("Wrong error: \(error)") }
    }

    @Test("Empty query → emptyQuery (before key lookup)")
    func emptyQuery() async {
        let tool = WebSearchTool(dependencies: makeDeps(secrets: StubSecretResolver(key: "k")),
                                 backend: RecordingBackend(results: [], recorder: .init()))
        do {
            _ = try await tool.call(WebSearchInput(query: "   "), context: ctx)
            Issue.record("Should throw")
        } catch WebSearchError.emptyQuery {
        } catch { Issue.record("Wrong error: \(error)") }
    }

    @Test("Tavily parser maps content → snippet")
    func tavilyParse() {
        let json = """
        { "results": [
            { "title": "T", "url": "https://u", "content": "C", "score": 0.9 }
        ] }
        """
        let results = TavilyWebSearchBackend.parse(Data(json.utf8))
        #expect(results.count == 1)
        #expect(results.first?.title == "T")
        #expect(results.first?.snippet == "C")
    }

    @Test("Tool descriptor: web.search behind webSearch permission, read-only")
    func descriptor() {
        let tool = WebSearchTool(dependencies: makeDeps(secrets: StubSecretResolver(key: "k")))
        #expect(WebSearchTool.name == ToolName("web.search"))
        #expect(WebSearchTool.permission == SwooshPermission.webSearch)
        #expect(WebSearchTool.risk == ToolRisk.readOnly)
        #expect(WebSearchTool.toolset == ToolsetID.web)
        _ = tool
    }
}

// MARK: - Registration

@Suite("WebSearchTool registration")
struct WebSearchRegistrationTests {

    @Test("web.search is registered by DefaultToolRegistrar")
    func registered() async {
        let firewall = SwooshFirewallActor(granted: Set(SwooshPermission.allCases))
        let audit = SwooshAuditLog()
        let approvals = InMemoryApprovalRequester(autoApprove: true)
        let deps = ToolDependencies(
            firewall: firewall, audit: audit, approvals: approvals,
            fileAccess: SafeFileAccessor(rootStore: InMemoryRootStore()),
            processRunner: StreamingProcessRunner()
        )
        let registry = ToolRegistry(firewall: firewall, audit: audit, approvals: approvals)
        await DefaultToolRegistrar.registerAll(into: registry, dependencies: deps)
        let schema = await registry.getToolSchema(name: ToolName("web.search"))
        #expect(schema != nil)
    }
}

// MARK: - Live smoke (gated on TAVILY_API_KEY)

@Suite("WebSearchTool live smoke")
struct WebSearchSmokeTests {

    @Test("Real Tavily search returns results")
    func liveSearch() async throws {
        guard let key = ProcessInfo.processInfo.environment["TAVILY_API_KEY"],
              !key.isEmpty else {
            return // no key — no-op pass
        }
        let tool = WebSearchTool(dependencies: makeDeps(secrets: StubSecretResolver(key: key)))
        let out = try await tool.call(WebSearchInput(query: "swift programming language", maxResults: 3),
                                      context: ctx)
        #expect(!out.results.isEmpty)
    }
}
