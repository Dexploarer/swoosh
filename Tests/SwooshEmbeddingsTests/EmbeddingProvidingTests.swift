// Tests/SwooshEmbeddingsTests/EmbeddingProvidingTests.swift — 0.9S
//
// Covers the default `embed(_ texts: [String])` extension method on
// `EmbeddingProviding` and the `EmbeddingProviderError` case
// descriptions. Both are part of the module's public surface but were
// untested before this audit pass.

import Foundation
import Testing
@testable import SwooshEmbeddings

@Suite("EmbeddingProviding default batch")
struct EmbeddingProvidingBatchTests {

    @Test("Default batch impl loops over single-text impl in order")
    func batchLoopPreservesOrder() async throws {
        let provider = IndexedStubProvider()
        let vectors = try await provider.embed(["a", "bb", "ccc"])
        #expect(vectors.count == 3)
        // IndexedStubProvider returns [Float(text.count)] so this also
        // checks that batch ordering matches input ordering.
        #expect(vectors[0] == [1.0])
        #expect(vectors[1] == [2.0])
        #expect(vectors[2] == [3.0])
    }

    @Test("Empty batch returns empty array without invoking single-text impl")
    func batchEmptyShortCircuits() async throws {
        let provider = IndexedStubProvider()
        let vectors = try await provider.embed([] as [String])
        #expect(vectors.isEmpty)
        #expect(await provider.callCount == 0)
    }

    @Test("Batch propagates errors from the first failing text")
    func batchPropagatesError() async {
        let provider = FailAtSecondTextProvider()
        do {
            _ = try await provider.embed(["ok-1", "fail", "ok-2"])
            Issue.record("expected throw")
        } catch let error as EmbeddingProviderError {
            switch error {
            case .requestFailed(let msg):
                #expect(msg == "second call failed")
            default:
                Issue.record("expected requestFailed, got \(error)")
            }
        } catch {
            Issue.record("expected EmbeddingProviderError, got \(error)")
        }
        // Only the first two calls should have been made — the third
        // is never attempted after the second throws.
        #expect(await provider.callCount == 2)
    }
}

@Suite("EmbeddingProviderError descriptions")
struct EmbeddingProviderErrorTests {

    @Test("Every case has a descriptive message")
    func allCasesHaveDescriptions() {
        #expect(EmbeddingProviderError.unsupportedPlatform.description
            == "Embeddings unavailable on this platform.")
        #expect(EmbeddingProviderError.languageNotSupported("xx").description
            .contains("xx"))
        #expect(EmbeddingProviderError.modelUnavailable("foo").description
            .contains("foo"))
        #expect(EmbeddingProviderError.requestFailed("boom").description
            .contains("boom"))
        #expect(EmbeddingProviderError.missingAPIKey("openai").description
            .contains("openai"))
    }

    @Test("Error type is Sendable")
    func isSendable() {
        let _: any Sendable = EmbeddingProviderError.unsupportedPlatform
        #expect(Bool(true))
    }
}

// MARK: - Stubs

/// Returns `[Float(text.count)]` for each input — lets tests assert
/// ordering by checking the vector contents.
private actor IndexedStubProvider: EmbeddingProviding {
    private(set) var callCount: Int = 0
    init() {}
    nonisolated var id: String { "indexed-stub" }
    nonisolated var displayName: String { "Indexed Stub" }
    nonisolated var isLocal: Bool { true }
    func dimension() async -> Int { 1 }
    func embed(_ text: String) async throws -> [Float] {
        callCount += 1
        return [Float(text.count)]
    }
}

/// Succeeds on call #1, throws on call #2, never reached on call #3.
private actor FailAtSecondTextProvider: EmbeddingProviding {
    private(set) var callCount: Int = 0
    init() {}
    nonisolated var id: String { "fail-second" }
    nonisolated var displayName: String { "Fail at second" }
    nonisolated var isLocal: Bool { true }
    func dimension() async -> Int { 1 }
    func embed(_ text: String) async throws -> [Float] {
        callCount += 1
        if callCount == 2 {
            throw EmbeddingProviderError.requestFailed("second call failed")
        }
        return [Float(callCount)]
    }
}
