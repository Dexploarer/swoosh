// MLXModelProviderTests.swift — verify the MLX → ModelProvider bridge.
// Real inference needs a downloaded model; these cover the pure logic
// (prompt flattening, identity) that does not.

import Testing
@testable import SwooshMLX
import SwooshCore

@Suite("MLXModelProvider")
struct MLXModelProviderTests {

    @Test("flatten produces a role-tagged prompt ending with an Assistant cue")
    func flattenFormatsPrompt() {
        let prompt = MLXModelProvider.flatten([
            ChatMessage(role: .system, content: "You are Swoosh."),
            ChatMessage(role: .user, content: "Hello"),
            ChatMessage(role: .assistant, content: "Hi"),
            ChatMessage(role: .user, content: "Help me"),
        ])
        #expect(prompt.contains("[System]\nYou are Swoosh."))
        #expect(prompt.contains("[User]\nHello"))
        #expect(prompt.contains("[Assistant]\nHi"))
        #expect(prompt.contains("[User]\nHelp me"))
        #expect(prompt.hasSuffix("[Assistant]\n"))
    }

    @Test("conforms to ModelProvider with a stable identity")
    func identity() {
        let provider = MLXModelProvider(modelID: "mlx-community/gemma-4-e4b-it-4bit")
        #expect(provider.providerID == "mlx-local")
        #expect(provider.modelName == "mlx-community/gemma-4-e4b-it-4bit")
        // Statically assert protocol conformance.
        let asProvider: any ModelProvider = provider
        #expect(asProvider.providerID == "mlx-local")
    }
}
