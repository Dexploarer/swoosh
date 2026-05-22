// Tests/SwooshLocalVoiceTests/CloningBackendTests.swift
// Version: 0.9R
//
// Validates that the cloning catalog entries (StyleTTS2, PocketTTS):
//   - exist with `supportsVoiceCloning = true`
//   - resolve through the LocalTTSResolver
//   - route through the LocalVoiceEngine dispatcher to the right backends
//   - have working FluidAudio managers (instantiation check)
//   - StyleTTS2 refuses to synth without a reference audio (cloning IS
//     its contract — no built-in default voice)
//
// Live cloning round-trip is gated on `SWOOSH_CLONING_LIVE=1` so CI
// skips the ~200 MB model downloads.

import XCTest
import FluidAudio
import SwooshVoiceProviders
@testable import SwooshLocalVoice

final class CloningBackendTests: XCTestCase {

    // MARK: - Catalog

    func test_styleTTS2_isInCatalogWithCloning() {
        let entry = LocalVoiceCatalog.styleTTS2
        XCTAssertTrue(entry.supportsVoiceCloning)
        XCTAssertEqual(entry.engineKind, .coreml)
        XCTAssertEqual(entry.family, "StyleTTS2")
    }

    func test_pocketTTS_isInCatalogWithCloning() {
        let entry = LocalVoiceCatalog.pocketTTS
        XCTAssertTrue(entry.supportsVoiceCloning)
        XCTAssertEqual(entry.engineKind, .coreml)
        XCTAssertEqual(entry.family, "PocketTTS")
    }

    func test_cloningCapable_includesBothNewEntries() {
        let ids = Set(LocalVoiceCatalog.cloningCapable.map(\.id))
        XCTAssertTrue(ids.contains(LocalVoiceCatalog.styleTTS2.id))
        XCTAssertTrue(ids.contains(LocalVoiceCatalog.pocketTTS.id))
        XCTAssertTrue(ids.contains(LocalVoiceCatalog.omniVoice.id))
        XCTAssertFalse(ids.contains(LocalVoiceCatalog.kokoro.id),
                       "Kokoro must NOT be in the cloning subset — it uses fixed voice packs")
    }

    func test_catalog_orderingPicksKokoroAsDefault() {
        // The smallest model is first in `all`, so the device-policy
        // picker doesn't accidentally default users to a heavier model.
        XCTAssertEqual(LocalVoiceCatalog.all.first?.id, LocalVoiceCatalog.kokoro.id)
    }

    // MARK: - Resolver + Router

    func test_resolver_mapsStyleTTS2Choice() {
        let p = LocalTTSResolver.provider(for: .styleTTS2Local)
        XCTAssertEqual(p?.model.id, LocalVoiceCatalog.styleTTS2.id)
        XCTAssertTrue(p?.supportsVoiceCloning ?? false)
    }

    func test_resolver_mapsPocketTTSChoice() {
        let p = LocalTTSResolver.provider(for: .pocketTTSLocal)
        XCTAssertEqual(p?.model.id, LocalVoiceCatalog.pocketTTS.id)
        XCTAssertTrue(p?.supportsVoiceCloning ?? false)
    }

    func test_router_advertisesCloningCases() {
        XCTAssertTrue(VoiceRouter.TTSChoice.styleTTS2Local.supportsCloning)
        XCTAssertTrue(VoiceRouter.TTSChoice.pocketTTSLocal.supportsCloning)
        XCTAssertTrue(VoiceRouter.TTSChoice.omniVoiceLocal.supportsCloning)
        XCTAssertFalse(VoiceRouter.TTSChoice.kokoroLocal.supportsCloning)
        XCTAssertFalse(VoiceRouter.TTSChoice.system.supportsCloning)
    }

    func test_router_cloningCasesAreLocalAndKeyFree() {
        for choice in [VoiceRouter.TTSChoice.styleTTS2Local, .pocketTTSLocal] {
            XCTAssertTrue(choice.isLocal, "\(choice.rawValue) must be on-device")
            XCTAssertFalse(choice.requiresAPIKey, "\(choice.rawValue) must not require an API key")
        }
    }

    // MARK: - FluidAudio managers exist (no network)

    func test_fluidAudioStyleTTS2Manager_isInstantiable() {
        XCTAssertNotNil(StyleTTS2Manager(), "FluidAudio.StyleTTS2Manager must construct without args")
    }

    func test_fluidAudioPocketTtsManager_isInstantiable() {
        XCTAssertNotNil(PocketTtsManager(), "FluidAudio.PocketTtsManager must construct without args")
    }

    // MARK: - StyleTTS2 contract: refuses synthesis without a reference

    func test_styleTTS2_requiresReferenceAudio() async throws {
        // The StyleTTS2 backend MUST refuse text-only synthesis (no
        // built-in default voice — cloning IS the model). We can verify
        // this without loading the model: the backend raises the error
        // before initialise() if reference is nil... wait, current
        // implementation initialises first. So this test exercises the
        // error path AFTER load — gated on env to avoid the download.
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["SWOOSH_CLONING_LIVE"] == "1",
            "Set SWOOSH_CLONING_LIVE=1 to run the live StyleTTS2 contract test"
        )
        let engine = LocalVoiceEngine(model: LocalVoiceCatalog.styleTTS2)
        do {
            _ = try await engine.synthesize(text: "should fail", referenceAudio: nil)
            XCTFail("StyleTTS2 must refuse synthesis without reference audio")
        } catch let error as LocalVoiceError {
            if case .synthesisFailed = error { /* expected */ }
            else { XCTFail("Wrong error type: \(error)") }
        }
    }

    // MARK: - Live cloning round-trips (gated)

    /// Live PocketTTS clone-and-synthesize using a short reference WAV
    /// captured via AVSpeechSynthesizer. Skipped unless
    /// `SWOOSH_CLONING_LIVE=1` is set.
    func test_live_pocketTTSCloning_producesAudio() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["SWOOSH_CLONING_LIVE"] == "1",
            "Set SWOOSH_CLONING_LIVE=1 to run the live PocketTTS cloning test"
        )
        let refURL = try await Self.makeReferenceWAV(text: "This is a reference voice sample.")
        defer { try? FileManager.default.removeItem(at: refURL) }

        let engine = LocalVoiceEngine(model: LocalVoiceCatalog.pocketTTS)
        let wav = try await engine.synthesize(
            text: "Hello in the cloned voice.",
            referenceAudio: refURL
        )
        XCTAssertGreaterThan(wav.count, 10_000, "Real PocketTTS cloning should emit substantial audio")
        XCTAssertEqual(Array(wav[0..<4]), Array("RIFF".utf8))
    }

    // MARK: - Helpers

    /// Captures a brief WAV via AppleFallbackBackend so the cloning
    /// tests have a reproducible reference clip without an audio file
    /// dependency in the repo.
    static func makeReferenceWAV(text: String) async throws -> URL {
        let backend = AppleFallbackBackend.shared
        let wav = try await backend.synthesize(
            text: text,
            voiceID: nil,
            referenceAudio: nil,
            model: LocalVoiceCatalog.kokoro
        )
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swoosh-ref-\(UUID().uuidString).wav")
        try wav.write(to: tmp)
        return tmp
    }
}
