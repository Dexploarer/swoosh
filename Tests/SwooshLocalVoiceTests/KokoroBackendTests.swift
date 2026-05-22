// Tests/SwooshLocalVoiceTests/KokoroBackendTests.swift
//
// Validates that the Kokoro catalog entry routes to the FluidAudio
// CoreML backend (not the Apple fallback) and that synthesis through
// the engine produces real audio. The model-download integration test
// is gated on `SWOOSH_KOKORO_LIVE=1` so CI / cold checkouts skip the
// ~80 MB FluidAudio model pull.

import XCTest
import FluidAudio
@testable import SwooshLocalVoice

final class KokoroBackendTests: XCTestCase {

    // MARK: - Catalog → backend wiring (no network)

    func test_kokoroCatalogEntry_targetsCoreML() {
        XCTAssertEqual(
            LocalVoiceCatalog.kokoro.engineKind, .coreml,
            "Kokoro must declare engineKind=.coreml so KokoroAneBackend is selected"
        )
    }

    func test_kokoroCatalogEntry_pointsAtFluidAudioWeights() {
        let url = LocalVoiceCatalog.kokoro.downloadURL
        XCTAssertEqual(url.host, "huggingface.co")
        XCTAssertTrue(
            url.path.contains("FluidInference") || url.path.contains("kokoro"),
            "Catalog URL should point at the FluidAudio CoreML bundle (got \(url.path))"
        )
    }

    func test_omniVoiceCatalogEntry_isWiredButFallsBack() {
        // OmniVoice has no Swift inference yet — the model entry exists
        // (so users can download + see the offering) but synthesis
        // routes through Apple fallback until sherpa-onnx ships.
        let omni = LocalVoiceCatalog.omniVoice
        XCTAssertEqual(omni.engineKind, .onnx, "OmniVoice catalog declares ONNX (future SherpaOnnxBackend)")
        XCTAssertTrue(omni.supportsVoiceCloning, "OmniVoice is the voice-cloning entry")
    }

    func test_sherpaOnnxBackend_reportsUnavailable() async {
        // Until a real sherpa-onnx Swift package ships, this backend
        // MUST refuse to load — that's the signal to the dispatcher
        // (and a regression alarm if someone accidentally wires it).
        do {
            try await SherpaOnnxBackend.shared.load(modelPath: nil, model: LocalVoiceCatalog.omniVoice)
            XCTFail("SherpaOnnxBackend.load() must throw until a real Swift implementation lands")
        } catch let error as LocalVoiceError {
            if case .backendNotAvailable = error {
                // expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - FluidAudio integration sanity (no network)

    func test_fluidAudioKokoroAneManager_isInstantiable() {
        // Catches dependency-resolution failures fast: if the FluidAudio
        // SPM dep ever breaks, this test fails before the network-gated
        // model-download test runs.
        let manager = KokoroAneManager()
        XCTAssertNotNil(manager, "FluidAudio.KokoroAneManager must construct without args")
    }

    // MARK: - Live inference (network + model download)

    /// Gated test: only runs when `SWOOSH_KOKORO_LIVE=1` is set in the
    /// environment. Downloads FluidAudio's CoreML Kokoro bundle on first
    /// run (~80 MB) and verifies real synthesis. Skip silently otherwise
    /// so CI stays fast.
    func test_live_kokoroSynthesis_producesAudio() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["SWOOSH_KOKORO_LIVE"] == "1",
            "Set SWOOSH_KOKORO_LIVE=1 to run the live Kokoro download + synthesis test"
        )
        let engine = LocalVoiceEngine(model: LocalVoiceCatalog.kokoro)
        let wav = try await engine.synthesize(text: "Hello from Swoosh, served by Kokoro on the Neural Engine.")
        XCTAssertGreaterThan(wav.count, 10_000, "Real Kokoro inference should emit substantial audio")
        // FluidAudio returns a complete WAV — header check.
        XCTAssertEqual(Array(wav[0..<4]), Array("RIFF".utf8))
        XCTAssertEqual(Array(wav[8..<12]), Array("WAVE".utf8))
    }
}
