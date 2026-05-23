// Tests/SwooshEmbeddingsTests/EmbeddingRouterTests.swift — 0.9S
//
// `EmbeddingRouter` is local-first: it always tries the injected local
// provider, and falls through to cloud only when (a) cloud was supplied
// AND (b) local threw. This test pins both happy paths and the error-
// propagation contract.

import Foundation
import Testing
@testable import SwooshEmbeddings

@Suite("EmbeddingRouter")
struct EmbeddingRouterTests {

    // MARK: - Identity constants

    @Test("Identity constants reflect the router shape")
    func identity() async {
        let router = EmbeddingRouter(local: StubProvider.constant([1.0]))
        #expect(router.id == "embedding-router")
        #expect(router.displayName == "Embeddings (router)")
        #expect(router.isLocal == true)
    }

    @Test("dimension delegates to the local provider")
    func dimensionDelegates() async {
        let router = EmbeddingRouter(
            local: StubProvider.constant([0.0, 0.0, 0.0])  // dim 3
        )
        #expect(await router.dimension() == 3)
    }

    // MARK: - Routing

    @Test("Local success short-circuits — cloud is never consulted")
    func localHappyPathSkipsCloud() async throws {
        let local = StubProvider.constant([1.0, 2.0, 3.0])
        let cloud = StubProvider.recordingFailure(error: .requestFailed("should not call"))
        let router = EmbeddingRouter(local: local, cloud: cloud)
        let result = try await router.embed("anything")
        #expect(result == [1.0, 2.0, 3.0])
        #expect(await cloud.callCount == 0)
    }

    @Test("Local failure with no cloud propagates the original error")
    func localFailureNoCloudPropagates() async {
        let local = StubProvider.throwing(.languageNotSupported("xx"))
        let router = EmbeddingRouter(local: local, cloud: nil)
        do {
            _ = try await router.embed("anything")
            Issue.record("expected throw")
        } catch let error as EmbeddingProviderError {
            switch error {
            case .languageNotSupported(let lang):
                #expect(lang == "xx")
            default:
                Issue.record("expected languageNotSupported, got \(error)")
            }
        } catch {
            Issue.record("expected EmbeddingProviderError, got \(error)")
        }
    }

    @Test("Local failure with cloud falls through to cloud")
    func localFailureFallsThroughToCloud() async throws {
        let local = StubProvider.throwing(.modelUnavailable("apple-nl"))
        let cloud = StubProvider.constant([9.0, 9.0])
        let router = EmbeddingRouter(local: local, cloud: cloud)
        let result = try await router.embed("anything")
        #expect(result == [9.0, 9.0])
        #expect(await cloud.callCount == 1)
    }
}

// MARK: - Stub provider

/// In-memory stub for EmbeddingProviding. Either returns a constant
/// vector or throws a configured error. Counts calls for verifying
/// the router short-circuited correctly.
actor StubProvider: EmbeddingProviding {
    enum Mode: Sendable {
        case constant([Float])
        case throwing(EmbeddingProviderError)
    }

    private let mode: Mode
    private(set) var callCount: Int = 0

    init(mode: Mode) { self.mode = mode }

    static func constant(_ vector: [Float]) -> StubProvider {
        StubProvider(mode: .constant(vector))
    }
    static func throwing(_ error: EmbeddingProviderError) -> StubProvider {
        StubProvider(mode: .throwing(error))
    }
    static func recordingFailure(error: EmbeddingProviderError) -> StubProvider {
        StubProvider(mode: .throwing(error))
    }

    nonisolated var id: String { "stub" }
    nonisolated var displayName: String { "Stub" }
    nonisolated var isLocal: Bool { true }

    func dimension() async -> Int {
        switch mode {
        case .constant(let v): return v.count
        case .throwing: return 0
        }
    }

    func embed(_ text: String) async throws -> [Float] {
        callCount += 1
        switch mode {
        case .constant(let v): return v
        case .throwing(let error): throw error
        }
    }
}
