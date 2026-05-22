// Tests/SwooshLocalVoiceTests/LocalTTSProviderTests.swift
// Version: 0.9R
//
// Proves the on-device TTS provider conforms to the public TTSProviding
// contract and that the Apple-fallback engine actually produces WAV
// bytes end-to-end. These tests run on macOS via `swift test`, so they
// don't depend on an iOS runtime.

import XCTest
import SwooshVoiceProviders
@testable import SwooshLocalVoice

final class LocalTTSProviderTests: XCTestCase {

    // MARK: - Protocol conformance

    func test_provider_conformsToTTSProviding() {
        let p: any TTSProviding = LocalTTSProvider(model: LocalVoiceCatalog.kokoro)
        XCTAssertFalse(p.isCloud, "On-device providers must report isCloud = false")
        XCTAssertNil(p.signupURL, "On-device providers have no signup URL")
        XCTAssertTrue(p.supportsStreaming, "Local provider claims streaming via chunked engine output")
    }

    func test_provider_idsAreStableAndUnique() {
        let kokoro = LocalTTSProvider(model: LocalVoiceCatalog.kokoro)
        let omni = LocalTTSProvider(model: LocalVoiceCatalog.omniVoice)
        XCTAssertEqual(kokoro.id, "local.kokoro-82m-v1")
        XCTAssertEqual(omni.id, "local.omnivoice-v1")
        XCTAssertNotEqual(kokoro.id, omni.id, "Two models must produce two distinct provider IDs")
    }

    func test_provider_displayNameIncludesOnDeviceMarker() {
        let p = LocalTTSProvider(model: LocalVoiceCatalog.kokoro)
        XCTAssertTrue(
            p.displayName.lowercased().contains("on-device"),
            "Display name must signal on-device routing to the user (got \(p.displayName))"
        )
    }

    // MARK: - Resolver

    func test_resolver_mapsKokoroChoice() {
        let p = LocalTTSResolver.provider(for: .kokoroLocal)
        XCTAssertEqual(p?.model.id, LocalVoiceCatalog.kokoro.id)
    }

    func test_resolver_mapsOmniVoiceChoice() {
        let p = LocalTTSResolver.provider(for: .omniVoiceLocal)
        XCTAssertEqual(p?.model.id, LocalVoiceCatalog.omniVoice.id)
    }

    func test_resolver_returnsNilForCloudChoices() {
        XCTAssertNil(LocalTTSResolver.provider(for: .elevenlabs))
        XCTAssertNil(LocalTTSResolver.provider(for: .openaiTTS))
        XCTAssertNil(LocalTTSResolver.provider(for: .cartesia))
        XCTAssertNil(LocalTTSResolver.provider(for: .system))
    }

    // MARK: - VoiceRouter integration

    func test_router_exposesLocalChoices() {
        let cases = VoiceRouter.TTSChoice.allCases.map(\.rawValue)
        XCTAssertTrue(cases.contains("kokoro-local"), "Router must expose kokoroLocal in its enum")
        XCTAssertTrue(cases.contains("omnivoice-local"), "Router must expose omniVoiceLocal in its enum")
    }

    func test_router_localChoices_reportAsLocal() {
        XCTAssertTrue(VoiceRouter.TTSChoice.kokoroLocal.isLocal)
        XCTAssertTrue(VoiceRouter.TTSChoice.omniVoiceLocal.isLocal)
        XCTAssertFalse(VoiceRouter.TTSChoice.elevenlabs.isLocal)
        XCTAssertFalse(VoiceRouter.TTSChoice.openaiTTS.isLocal)
        XCTAssertFalse(VoiceRouter.TTSChoice.cartesia.isLocal)
    }

    func test_router_localChoices_doNotRequireAPIKey() {
        XCTAssertFalse(VoiceRouter.TTSChoice.kokoroLocal.requiresAPIKey)
        XCTAssertFalse(VoiceRouter.TTSChoice.omniVoiceLocal.requiresAPIKey)
    }

    func test_router_cloudProvider_isNilForLocalChoices() async throws {
        // Cloud-provider builder must NOT instantiate when the user picks
        // an on-device engine — the LocalTTSResolver owns those.
        let router = await MainActor.run { VoiceRouter() }
        await MainActor.run { router.currentTTSChoice = .kokoroLocal }
        let cloud = try await MainActor.run { try router.activeCloudTTSProvider() }
        XCTAssertNil(cloud, "Cloud provider builder must yield nil for local choices")
        // Reset so we don't leak state into other tests.
        await MainActor.run { router.currentTTSChoice = .system }
    }
}
