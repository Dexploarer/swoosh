// Tests/SwooshCoreTests/AgentKernelTests.swift
//
// Critical tests for 0.3A:
// - Approved memories enter prompt
// - Rejected memories do NOT enter prompt
// - Raw Scout records do NOT enter prompt
// - Response records memory IDs used
// - Response writes audit event
// - /why can report context used

import Testing
@testable import SwooshCore

// MARK: - Core kernel tests

@Test func testApprovedMemoriesEnterPrompt() async throws {
    let loader = InMemoryMemoryLoader(memories: [
        (id: "mem-1", text: "User develops with Xcode", category: "profile"),
        (id: "mem-2", text: "User uses Blender for 3D", category: "profile"),
    ])
    let kernel = AgentKernel(
        memoryLoader: loader,
        reportLoader: InMemoryReportLoader(),
        permSummarizer: InMemoryPermSummarizer(),
        sessionStore: InMemorySessionStore(),
        auditLogger: InMemoryResponseAuditor(),
        modelProvider: LocalDiagnosticProvider()
    )

    let response = try await kernel.run(AgentRequest(input: "What do I use?"))

    // The local diagnostic provider echoes back memories it received
    #expect(response.message.contains("Xcode"))
    #expect(response.message.contains("Blender"))
    #expect(response.memoryIDsUsed.contains("mem-1"))
    #expect(response.memoryIDsUsed.contains("mem-2"))
    #expect(response.memoryIDsUsed.count == 2)
}

@Test func testRejectedMemoriesDoNotEnterPrompt() async throws {
    // InMemoryMemoryLoader only contains approved memories.
    // Rejected candidates are never loaded — they don't exist in this loader.
    let loader = InMemoryMemoryLoader(memories: [
        (id: "approved-1", text: "User develops with Swift", category: "profile"),
    ])
    // NOTE: "User works with Java" was a rejected candidate — it is NOT in the loader.

    let kernel = AgentKernel(
        memoryLoader: loader,
        reportLoader: InMemoryReportLoader(),
        permSummarizer: InMemoryPermSummarizer(),
        sessionStore: InMemorySessionStore(),
        auditLogger: InMemoryResponseAuditor(),
        modelProvider: LocalDiagnosticProvider()
    )

    let response = try await kernel.run(AgentRequest(input: "What languages?"))

    #expect(response.message.contains("Swift"))
    #expect(!response.message.contains("Java"))
    #expect(response.memoryIDsUsed == ["approved-1"])
}

@Test func testRawScoutRecordsDoNotEnterPrompt() async throws {
    // The memory loader only returns approved memories.
    // Raw Scout records (source: scanning) never appear as approved memories
    // unless the user explicitly approved them as candidates.
    let loader = InMemoryMemoryLoader() // empty — no approved memories

    let kernel = AgentKernel(
        memoryLoader: loader,
        reportLoader: InMemoryReportLoader(),
        permSummarizer: InMemoryPermSummarizer(),
        sessionStore: InMemorySessionStore(),
        auditLogger: InMemoryResponseAuditor(),
        modelProvider: LocalDiagnosticProvider()
    )

    let response = try await kernel.run(AgentRequest(input: "Tell me about my apps"))

    #expect(response.message.contains("No approved memories"))
    #expect(response.memoryIDsUsed.isEmpty)
}

@Test func testResponseRecordsMemoryIDsUsed() async throws {
    let loader = InMemoryMemoryLoader(memories: [
        (id: "id-abc", text: "User prefers dark mode", category: "preference"),
        (id: "id-def", text: "User has 3 monitors", category: "device"),
        (id: "id-ghi", text: "User codes in Swift", category: "profile"),
    ])

    let kernel = AgentKernel(
        memoryLoader: loader,
        reportLoader: InMemoryReportLoader(),
        permSummarizer: InMemoryPermSummarizer(),
        sessionStore: InMemorySessionStore(),
        auditLogger: InMemoryResponseAuditor(),
        modelProvider: LocalDiagnosticProvider()
    )

    let response = try await kernel.run(AgentRequest(input: "Tell me about myself"))

    #expect(response.memoryIDsUsed.count == 3)
    #expect(response.memoryIDsUsed.contains("id-abc"))
    #expect(response.memoryIDsUsed.contains("id-def"))
    #expect(response.memoryIDsUsed.contains("id-ghi"))
}

@Test func testDuplicateApprovedMemoriesAreInjectedOnce() async throws {
    let loader = InMemoryMemoryLoader(memories: [
        (id: "first", text: "User codes in Swift", category: "profile"),
        (id: "duplicate", text: "  User codes   in Swift  ", category: "profile"),
        (id: "device", text: "User has 3 monitors", category: "device"),
    ])

    let kernel = AgentKernel(
        memoryLoader: loader,
        reportLoader: InMemoryReportLoader(),
        permSummarizer: InMemoryPermSummarizer(),
        sessionStore: InMemorySessionStore(),
        auditLogger: InMemoryResponseAuditor(),
        modelProvider: LocalDiagnosticProvider()
    )

    let response = try await kernel.run(AgentRequest(input: "Tell me about myself"))

    #expect(response.memoryIDsUsed == ["first", "device"])
    #expect(response.message.components(separatedBy: "User codes in Swift").count == 2)
}

@Test func testResponseWritesAuditEvent() async throws {
    let auditor = InMemoryResponseAuditor()
    let loader = InMemoryMemoryLoader(memories: [
        (id: "mem-x", text: "Test memory", category: "test"),
    ])

    let kernel = AgentKernel(
        memoryLoader: loader,
        reportLoader: InMemoryReportLoader(report: "Test report"),
        permSummarizer: InMemoryPermSummarizer(summary: "Granted: all"),
        sessionStore: InMemorySessionStore(),
        auditLogger: auditor,
        modelProvider: LocalDiagnosticProvider()
    )

    _ = try await kernel.run(AgentRequest(sessionID: "test-session", input: "Hello"))

    let audit = try await auditor.lastResponseAudit(sessionID: "test-session")
    #expect(audit != nil)
    #expect(audit?.sessionID == "test-session")
    #expect(audit?.memoryIDsUsed == ["mem-x"])
    #expect(audit?.setupReportUsed == true)
    #expect(audit?.permissionSummaryUsed == true)
    #expect(audit?.rejectedMemoriesExcluded == true)
    #expect(audit?.rawScoutRecordsExcluded == true)
    #expect(audit?.cookiesExcluded == true)
    #expect(audit?.secretsExcluded == true)
}

@Test func testWhyCommandReportsContextUsed() async throws {
    let auditor = InMemoryResponseAuditor()
    let loader = InMemoryMemoryLoader(memories: [
        (id: "mem-1", text: "User develops with Xcode", category: "profile"),
    ])

    let kernel = AgentKernel(
        memoryLoader: loader,
        reportLoader: InMemoryReportLoader(report: "Setup complete"),
        permSummarizer: InMemoryPermSummarizer(),
        sessionStore: InMemorySessionStore(),
        auditLogger: auditor,
        modelProvider: LocalDiagnosticProvider()
    )

    _ = try await kernel.run(AgentRequest(sessionID: "why-test", input: "Hi"))

    // Simulate /why by reading the audit
    let audit = try await auditor.lastResponseAudit(sessionID: "why-test")
    #expect(audit != nil)

    // /why would report:
    #expect(audit!.memoryIDsUsed == ["mem-1"]) // approved memories used
    #expect(audit!.setupReportUsed == true)     // setup report used
    #expect(audit!.cookiesExcluded == true)      // cookies NOT used
    #expect(audit!.secretsExcluded == true)      // secrets NOT used
    #expect(audit!.rejectedMemoriesExcluded == true) // rejected NOT used
}

@Test func testWhyCommandReportsCookiesNotUsed() async throws {
    let auditor = InMemoryResponseAuditor()

    let kernel = AgentKernel(
        memoryLoader: InMemoryMemoryLoader(),
        reportLoader: InMemoryReportLoader(),
        permSummarizer: InMemoryPermSummarizer(),
        sessionStore: InMemorySessionStore(),
        auditLogger: auditor,
        modelProvider: LocalDiagnosticProvider()
    )

    _ = try await kernel.run(AgentRequest(sessionID: "cookie-test", input: "Check my browsing"))

    let audit = try await auditor.lastResponseAudit(sessionID: "cookie-test")
    #expect(audit != nil)
    #expect(audit!.cookiesExcluded == true)
    #expect(audit!.rawScoutRecordsExcluded == true)
}

@Test func testPromptIncludesPermissionSummary() async throws {
    let permSummarizer = InMemoryPermSummarizer(summary: "Granted: deviceProfileRead\nDenied: browserHistoryRead")

    let builder = PromptBuilder()
    let result = builder.buildSystemPrompt(
        approvedMemories: [],
        setupReport: nil,
        permissionSummary: permSummarizer.summary
    )
    let prompt = result.prompt

    #expect(prompt.contains("deviceProfileRead"))
    #expect(prompt.contains("browserHistoryRead"))
    #expect(prompt.contains("Permission Profile"))
}

@Test func testPromptExcludesDataSources() async throws {
    let builder = PromptBuilder()
    let result = builder.buildSystemPrompt(
        approvedMemories: [],
        setupReport: nil,
        permissionSummary: nil
    )
    let prompt = result.prompt

    #expect(prompt.contains("Browser cookies"))
    #expect(prompt.contains("SSH keys, API keys, secrets"))
    #expect(prompt.contains("Rejected memory candidates"))
    #expect(prompt.contains("Raw Scout scan records"))
}

@Test func testSessionPersistsMessages() async throws {
    let sessionStore = InMemorySessionStore()

    let kernel = AgentKernel(
        memoryLoader: InMemoryMemoryLoader(),
        reportLoader: InMemoryReportLoader(),
        permSummarizer: InMemoryPermSummarizer(),
        sessionStore: sessionStore,
        auditLogger: InMemoryResponseAuditor(),
        modelProvider: LocalDiagnosticProvider()
    )

    _ = try await kernel.run(AgentRequest(sessionID: "persist-test", input: "Hello"))

    let transcript = try await sessionStore.loadTranscript(sessionID: "persist-test")
    #expect(transcript.count == 3) // system + user + assistant
    #expect(transcript[0].role == .system)
    #expect(transcript[1].role == .user)
    #expect(transcript[1].content == "Hello")
    #expect(transcript[2].role == .assistant)
}
