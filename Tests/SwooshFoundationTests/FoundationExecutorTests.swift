// Tests/SwooshFoundationTests/FoundationExecutorTests.swift — 0.9Q
//
// Covers the `SwooshClient.SwooshExecutor` conformance on Apple
// FoundationModels. The real model path requires Apple Intelligence
// which CI cannot guarantee, so the test surface is:
//   • Executor constructs and is `Sendable`.
//   • Stub branch (`#else`) throws `.unavailable` on every `run`.
//   • The prompt flattener emits the same `[User]\n…\n\n[Assistant]\n`
//     shape the Provider would produce for a single-message transcript.

import Testing
import Foundation
import SwooshClient
import SwooshCore
@testable import SwooshFoundation

@Suite("FoundationExecutor")
struct FoundationExecutorTests {

    @Test("Executor is an actor (Sendable)")
    func sendable() {
        let executor = FoundationExecutor()
        let _: any Sendable = executor
        #expect(Bool(true))
    }

    #if !canImport(FoundationModels)
    @Test("Stub branch throws .unavailable on every run")
    func stubBranchThrowsUnavailable() async {
        let executor = FoundationExecutor()
        let request = ChatRequest(sessionID: "s1", input: "ping")
        do {
            _ = try await executor.run(request)
            Issue.record("expected throw")
        } catch FoundationModelProviderError.unavailable {
            // expected
        } catch {
            Issue.record("expected .unavailable, got \(error)")
        }
    }
    #endif
}

@Suite("FoundationModelPrompt.flatten")
struct FoundationModelPromptFlattenTests {
    // FoundationModelPrompt is internal — accessible via @testable.
    // SwooshCore.ChatMessage / ChatRole let us construct deterministic
    // transcripts without touching the model.

    @Test("Empty transcript still emits the open Assistant cue")
    func emptyTranscript() {
        let prompt = FoundationModelPrompt.flatten([])
        #expect(prompt == "[Assistant]\n")
    }

    @Test("Single user turn produces [User]…[Assistant] shape")
    func singleUserTurn() {
        let prompt = FoundationModelPrompt.flatten([
            chat(.user, "hello")
        ])
        #expect(prompt.contains("[User]\nhello"))
        #expect(prompt.hasSuffix("[Assistant]\n"))
    }

    @Test("All four roles get their own tag")
    func allRoles() {
        let prompt = FoundationModelPrompt.flatten([
            chat(.system, "you are detour"),
            chat(.user, "hi"),
            chat(.assistant, "hello"),
            chat(.tool, "result"),
        ])
        #expect(prompt.contains("[System]\nyou are detour"))
        #expect(prompt.contains("[User]\nhi"))
        #expect(prompt.contains("[Assistant]\nhello"))
        #expect(prompt.contains("[Tool]\nresult"))
        // Trailing open-assistant cue is still present so the model
        // knows the turn boundary.
        #expect(prompt.hasSuffix("[Assistant]\n"))
    }

    @Test("flattenUserInput matches single-user-turn shape")
    func flattenUserInputMatchesSingleTurn() {
        // Both helpers should produce the same wire shape when the only
        // transcript content is one bare user message — this is what
        // FoundationExecutor relies on.
        let viaFull = FoundationModelPrompt.flatten([chat(.user, "ping")])
        let viaBare = FoundationModelPrompt.flattenUserInput("ping")
        #expect(viaBare == viaFull)
    }

    @Test("Multi-line content is preserved verbatim inside its role block")
    func multilineContent() {
        let prompt = FoundationModelPrompt.flatten([
            chat(.user, "line one\nline two")
        ])
        #expect(prompt.contains("[User]\nline one\nline two"))
    }

    // MARK: - Helpers

    private func chat(
        _ role: ChatRole,
        _ content: String
    ) -> ChatMessage {
        ChatMessage(role: role, content: content)
    }
}
