// Tests/SwooshKitTests/SwooshKitTests.swift — Top-level SDK
//
// SwooshKit is the public entry point. These tests cover:
//   • SwooshConfiguration default values
//   • Swoosh.configure { ... } with the LocalDiagnosticProvider fallback
//   • Swoosh.ask(_:sessionID:) end-to-end against a stub provider
//   • LocalKernelExecutor wire-format conversion
//
// We deliberately avoid the ActantDB code path; tests run with
// ACTANT_BASE_URL unset so the InMemory* defaults are exercised.

import Testing
import Foundation
@testable import SwooshKit
@testable import SwooshClient
@testable import SwooshCore

// MARK: - SwooshConfiguration

@Suite("SwooshConfiguration")
struct SwooshConfigurationTests {

    @Test("Defaults are nil/empty")
    func defaults() {
        let config = SwooshConfiguration()
        #expect(config.modelProvider == nil)
        #expect(config.memoryLoader == nil)
        #expect(config.reportLoader == nil)
        #expect(config.permSummarizer == nil)
        #expect(config.sessionStore == nil)
        #expect(config.auditLogger == nil)
        #expect(config.toolRegistry == nil)
    }

    @Test("Custom modelProvider is preserved")
    func customProvider() {
        var config = SwooshConfiguration()
        config.modelProvider = LocalDiagnosticProvider()
        #expect(config.modelProvider != nil)
    }
}

// MARK: - Swoosh.configure

@Suite("Swoosh.configure")
struct SwooshConfigureTests {

    @Test("Default configure builds with LocalDiagnosticProvider")
    func defaultConfigure() async throws {
        let swoosh = try await Swoosh.configure { _ in }
        // Just checking the object builds and the kernel is set
        _ = swoosh.kernel
        #expect(swoosh.toolLoop == nil)
    }

    @Test("Custom provider is wired into the kernel")
    func customProvider() async throws {
        let swoosh = try await Swoosh.configure { config in
            config.modelProvider = StubProvider(reply: "from-stub")
        }
        let response = try await swoosh.ask("hello", sessionID: "test-session-1")
        #expect(response.message == "from-stub")
        #expect(response.sessionID == "test-session-1")
    }

    @Test("Default session id is used when omitted")
    func defaultSessionID() async throws {
        let swoosh = try await Swoosh.configure { config in
            config.modelProvider = StubProvider(reply: "ok")
        }
        let response = try await swoosh.ask("hello")
        #expect(response.sessionID == "default")
    }

    @Test("Same instance is reusable across calls")
    func reusable() async throws {
        let swoosh = try await Swoosh.configure { config in
            config.modelProvider = StubProvider(reply: "ok")
        }
        let r1 = try await swoosh.ask("hi", sessionID: "s1")
        let r2 = try await swoosh.ask("hi", sessionID: "s2")
        #expect(r1.sessionID == "s1")
        #expect(r2.sessionID == "s2")
    }
}

// MARK: - LocalKernelExecutor

@Suite("LocalKernelExecutor")
struct LocalKernelExecutorTests {

    @Test("Translates ChatRequest to AgentRequest and back")
    func roundTrip() async throws {
        let swoosh = try await Swoosh.configure { config in
            config.modelProvider = StubProvider(reply: "executor-reply")
        }
        let executor = LocalKernelExecutor(swoosh: swoosh)
        let response = try await executor.run(ChatRequest(sessionID: "exec-1", input: "hi"))
        #expect(response.message == "executor-reply")
        #expect(response.sessionID == "exec-1")
        #expect(response.modelUsed == "stub-model")
    }

    @Test("Initializes with kernel directly")
    func initWithKernel() async throws {
        let swoosh = try await Swoosh.configure { config in
            config.modelProvider = StubProvider(reply: "kernel-direct")
        }
        let executor = LocalKernelExecutor(kernel: swoosh.kernel)
        let response = try await executor.run(ChatRequest(sessionID: "kd-1", input: "hi"))
        #expect(response.message == "kernel-direct")
    }
}

// MARK: - StubProvider

private struct StubProvider: ModelProvider, Sendable {
    let providerID: String = "stub"
    let modelName: String = "stub-model"
    let reply: String

    func complete(_ request: ModelCompletionRequest) async throws -> ModelCompletionResponse {
        ModelCompletionResponse(
            content: reply,
            model: modelName,
            usage: ModelUsage(promptTokens: 1, completionTokens: 1, totalTokens: 2),
            toolCalls: [],
            isToolCallMode: false
        )
    }
}
