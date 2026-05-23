// Tests/SwooshFoundationTests/FoundationModelProviderTests.swift — 0.9Q
//
// Covers `FoundationModelProvider` identity (always available) and the
// `#else` stub branch's `.unavailable` error contract (only fires on
// non-FoundationModels builds, but the test is compiled on every
// platform). Avoids invoking the real model — Apple Intelligence
// capability is not present on CI runners.

import Testing
import Foundation
import SwooshCore
@testable import SwooshFoundation

@Suite("FoundationModelProvider")
struct FoundationModelProviderTests {

    @Test("Provider exposes stable identity constants")
    func identityConstants() {
        let provider = FoundationModelProvider()
        #expect(provider.providerID == "apple-foundation")
        #expect(provider.modelName == "apple-on-device")
    }

    @Test("Provider conforms to ModelProvider (Sendable)")
    func conformsToModelProvider() {
        let provider = FoundationModelProvider()
        let _: any ModelProvider = provider
        let _: any Sendable = provider
        #expect(Bool(true))
    }

    #if !canImport(FoundationModels)
    // Only the stub branch is testable without Apple Intelligence; on
    // canImport platforms invoking the real model would hit Apple's
    // runtime which CI cannot exercise.
    @Test("Stub branch throws .unavailable on every call")
    func stubBranchThrowsUnavailable() async {
        let provider = FoundationModelProvider()
        let request = ModelCompletionRequest(messages: [
            ChatMessage(role: .user, content: "ping")
        ])
        do {
            _ = try await provider.complete(request)
            Issue.record("expected throw")
        } catch FoundationModelProviderError.unavailable {
            // expected
        } catch {
            Issue.record("expected .unavailable, got \(error)")
        }
    }
    #endif
}
