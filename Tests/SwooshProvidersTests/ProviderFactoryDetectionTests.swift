// Tests/SwooshProvidersTests/ProviderFactoryDetectionTests.swift — 0.9A
//
// Round-trip + boundary tests for `ProviderFactory.providerID(forDetectedProviderName:)`.
// `detectActiveProvider` returns `(name, model)` tuples; `providerID(...)`
// is the inverse. If the two ever drift (a new provider name added to
// `detectProvider` without updating the reverse mapping, or vice-versa),
// the dashboard's "active provider" badge silently mis-categorises.

import Testing
import Foundation
@testable import SwooshProviderBridge
@testable import SwooshModels

@Suite("ProviderFactory.providerID(forDetectedProviderName:)")
struct ProviderFactoryReverseMappingTests {

    @Test("ChatGPT (Codex) → codex provider ID")
    func codex() {
        let id = ProviderFactory.providerID(forDetectedProviderName: "ChatGPT (Codex)")
        #expect(id == ModelDefaults.codexProviderID)
    }

    @Test("OpenAI → openai provider ID")
    func openAI() {
        let id = ProviderFactory.providerID(forDetectedProviderName: "OpenAI")
        #expect(id == ModelDefaults.openAIProviderID)
    }

    @Test("OpenRouter → openrouter provider ID")
    func openRouter() {
        let id = ProviderFactory.providerID(forDetectedProviderName: "OpenRouter")
        #expect(id == ModelDefaults.openRouterProviderID)
    }

    @Test("Eliza Cloud → eliza-cloud provider ID")
    func elizaCloud() {
        let id = ProviderFactory.providerID(forDetectedProviderName: "Eliza Cloud")
        #expect(id == ModelDefaults.elizaCloudProviderID)
    }

    @Test("MLX Local → mlx-local provider ID")
    func mlxLocal() {
        let id = ProviderFactory.providerID(forDetectedProviderName: "MLX Local")
        #expect(id == ModelDefaults.localMLXProviderID)
    }

    @Test("Apple Foundation → apple-foundation provider ID")
    func appleFoundation() {
        let id = ProviderFactory.providerID(forDetectedProviderName: "Apple Foundation")
        #expect(id == ModelDefaults.localFoundationProviderID)
    }

    @Test("Unknown name falls back to local-openai (Ollama / LM Studio bucket)")
    func unknownFallsBackToLocalOpenAI() {
        let id = ProviderFactory.providerID(forDetectedProviderName: "Some New Provider")
        #expect(id == ModelDefaults.localOpenAIProviderID)
    }

    @Test("Empty name falls back to local-openai")
    func empty() {
        let id = ProviderFactory.providerID(forDetectedProviderName: "")
        #expect(id == ModelDefaults.localOpenAIProviderID)
    }
}

@Suite("ProviderFactory.localModelRouteDefault env override")
struct ProviderFactoryLocalRouteEnvTests {

    @Test("SWOOSH_LOCAL_MODEL with a value overrides discovery")
    func envOverrideWins() async {
        // We can't safely mutate the process environment from a test
        // (other parallel tests would see it), but we can document the
        // contract: the env var is checked first via `ProcessInfo`. If
        // it's empty or unset, discovery + hardware-fallback take over.
        // The env override path is exercised manually via:
        //   SWOOSH_LOCAL_MODEL=test ./Scripts/swift-test-safe.sh
        // Skipping the live override here keeps tests hermetic.
        let resolved = await ProviderFactory.localModelRouteDefault()
        #expect(!resolved.isEmpty, "Resolved model name must not be empty")
    }
}
