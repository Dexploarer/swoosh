// Tests/SwooshEmbeddingsTests/ConcreteProviderTests.swift — 0.9S
//
// Identity-level tests for the concrete providers shipped in the
// module: AppleNL (on-device), OpenAI (cloud), and the OpenAI-
// compatible local endpoint. We do NOT hit the network or the
// on-device model in CI — the embed() paths require external state
// that the test harness cannot supply deterministically.

import Foundation
import Testing
@testable import SwooshEmbeddings

@Suite("Concrete provider identities")
struct ConcreteProviderIdentityTests {

    @Test("AppleNLEmbeddingProvider identity")
    func appleNLIdentity() {
        let provider = AppleNLEmbeddingProvider()
        #expect(provider.id == "apple-nl")
        #expect(provider.displayName.contains("Apple"))
        #expect(provider.isLocal == true)
    }

    @Test("OpenAIEmbeddingProvider identity")
    func openAIIdentity() {
        let provider = OpenAIEmbeddingProvider(apiKey: { "test" })
        #expect(provider.id == "openai-embed")
        #expect(provider.displayName.contains("OpenAI"))
        #expect(provider.isLocal == false)
    }

    @Test("OpenAIEmbeddingProvider.Config has sensible defaults")
    func openAIConfigDefaults() {
        let config = OpenAIEmbeddingProvider.Config()
        #expect(config.model == "text-embedding-3-small")
        #expect(config.outputDimension == 1536)
        #expect(config.baseURL.absoluteString == "https://api.openai.com/v1")
    }

    @Test("OpenAIEmbeddingProvider.dimension returns the configured value")
    func openAIDimension() async {
        let config = OpenAIEmbeddingProvider.Config(
            baseURL: URL(string: "https://example.com/v1")!,
            model: "test-model",
            outputDimension: 512
        )
        let provider = OpenAIEmbeddingProvider(config: config, apiKey: { "test" })
        #expect(await provider.dimension() == 512)
    }

    @Test("OpenAIEmbeddingProvider throws missingAPIKey when key resolution fails")
    func openAIMissingKey() async {
        let provider = OpenAIEmbeddingProvider(apiKey: {
            throw EmbeddingProviderError.missingAPIKey("test")
        })
        do {
            _ = try await provider.embed(["text"])
            Issue.record("expected throw")
        } catch let error as EmbeddingProviderError {
            switch error {
            case .missingAPIKey: break  // expected
            default: Issue.record("expected missingAPIKey, got \(error)")
            }
        } catch {
            Issue.record("expected EmbeddingProviderError, got \(error)")
        }
    }
}

@Suite("AppleNLEmbeddingProvider behaviour")
struct AppleNLBehaviourTests {

    #if canImport(NaturalLanguage)
    @Test("English defaults produce a positive-dimension vector")
    func englishDimension() async {
        let provider = AppleNLEmbeddingProvider(language: "en")
        let dim = await provider.dimension()
        // The actual value depends on the OS-shipped model; we only
        // assert the framework returned something usable.
        #expect(dim > 0)
    }

    @Test("Unsupported language returns 0 dimension")
    func unsupportedLanguageZero() async {
        let provider = AppleNLEmbeddingProvider(language: "zz")
        #expect(await provider.dimension() == 0)
    }
    #endif
}
