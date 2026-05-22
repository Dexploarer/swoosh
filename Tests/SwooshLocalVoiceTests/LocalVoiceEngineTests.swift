// Tests/SwooshLocalVoiceTests/LocalVoiceEngineTests.swift
// Version: 0.9R
//
// End-to-end: the AppleFallbackBackend behind LocalVoiceEngine actually
// synthesises audio bytes. The output is a real WAV (RIFF/WAVE header
// present + data chunk non-empty), so the entire audio loop is provably
// working today even though the ONNX-runtime swap is still pending.

import XCTest
@testable import SwooshLocalVoice

final class LocalVoiceEngineTests: XCTestCase {

    func test_engine_load_isIdempotent() async throws {
        let engine = LocalVoiceEngine(model: LocalVoiceCatalog.kokoro)
        try await engine.load(modelPath: nil)
        try await engine.load(modelPath: nil)  // must not throw on second call
        let state = await engine.loadState
        XCTAssertEqual(state, .ready)
    }

    func test_engine_synthesize_producesNonEmptyWAV() async throws {
        // The Apple-fallback backend should always return SOME audio
        // for non-trivial input. Empty WAV would mean the synthesizer
        // never completed.
        let engine = LocalVoiceEngine(model: LocalVoiceCatalog.kokoro)
        let data = try await engine.synthesize(text: "Hello from Swoosh local voice.")
        XCTAssertGreaterThan(data.count, 100, "WAV should contain header + audio samples")
    }

    func test_engine_synthesize_emitsValidWAVHeader() async throws {
        let engine = LocalVoiceEngine(model: LocalVoiceCatalog.kokoro)
        let data = try await engine.synthesize(text: "Header check.")

        // RIFF/WAVE/fmt /data markers at the canonical offsets.
        XCTAssertGreaterThan(data.count, 44, "WAV must be at least 44 bytes (header alone)")
        XCTAssertEqual(Array(data[0..<4]), Array("RIFF".utf8), "Missing RIFF marker")
        XCTAssertEqual(Array(data[8..<12]), Array("WAVE".utf8), "Missing WAVE marker")
        XCTAssertEqual(Array(data[12..<16]), Array("fmt ".utf8), "Missing fmt  marker")
        // The "data" marker lives at offset 36 in a standard 16-byte fmt chunk.
        XCTAssertEqual(Array(data[36..<40]), Array("data".utf8), "Missing data marker")
    }

    func test_engine_stream_emitsAtLeastOneChunk() async throws {
        let engine = LocalVoiceEngine(model: LocalVoiceCatalog.kokoro)
        let stream = await engine.synthesizeStream(text: "Stream check.")
        var chunkCount = 0
        var totalBytes = 0
        for try await chunk in stream {
            chunkCount += 1
            totalBytes += chunk.count
        }
        XCTAssertGreaterThan(chunkCount, 0, "Stream must yield at least one chunk")
        XCTAssertGreaterThan(totalBytes, 0, "Stream chunks must contain audio data")
    }
}
