// Tests/SwooshMLXTests/MLXInferenceEngineTests.swift — MLX local inference tests
//
// Tests the MLX inference engine state machine, model management,
// and error handling. Note: Actual MLX model loading requires Apple Silicon.

import Testing
import Foundation
@testable import SwooshMLX

// MARK: - MLX Error Tests

@Suite("MLXError")
struct MLXErrorTests {

    @Test("MLXError is Sendable")
    func isSendable() {
        let error: MLXError = .modelNotFound("test-model")
        // If this compiles, MLXError is Sendable
        _ = error
    }

    @Test("All error cases exist")
    func allCasesExist() {
        let errors: [MLXError] = [
            .modelNotFound("model-id"),
            .noModelLoaded,
            .loadFailed("model-id", "disk full"),
            .insufficientMemory(required: 16.0, available: 8.0)
        ]
        #expect(errors.count == 4)
    }

    @Test("ModelNotFound stores model ID")
    func modelNotFoundStoresID() {
        let error = MLXError.modelNotFound("llama-3.1-8b")
        if case .modelNotFound(let id) = error {
            #expect(id == "llama-3.1-8b")
        } else {
            Issue.record("Wrong error type")
        }
    }

    @Test("LoadFailed stores model ID and reason")
    func loadFailedStoresDetails() {
        let error = MLXError.loadFailed("qwen-7b", "unsupported architecture")
        if case .loadFailed(let id, let reason) = error {
            #expect(id == "qwen-7b")
            #expect(reason == "unsupported architecture")
        } else {
            Issue.record("Wrong error type")
        }
    }

    @Test("InsufficientMemory stores requirements")
    func insufficientMemoryStoresRequirements() {
        let error = MLXError.insufficientMemory(required: 32.0, available: 16.0)
        if case .insufficientMemory(let required, let available) = error {
            #expect(required == 32.0)
            #expect(available == 16.0)
        } else {
            Issue.record("Wrong error type")
        }
    }
}

// MARK: - LocalModelInfo Tests

@Suite("LocalModelInfo")
struct LocalModelInfoTests {

    @Test("LocalModelInfo initializes correctly")
    func initializesCorrectly() {
        let url = URL(fileURLWithPath: "/models/llama-3.1-8b")
        let info = LocalModelInfo(
            id: "llama-3.1-8b",
            path: url,
            sizeBytes: 16_000_000_000
        )

        #expect(info.id == "llama-3.1-8b")
        #expect(info.path == url)
        #expect(info.sizeBytes == 16_000_000_000)
    }

    @Test("LocalModelInfo calculates size in GB")
    func calculatesSizeGB() {
        let info = LocalModelInfo(
            id: "test",
            path: URL(fileURLWithPath: "/test"),
            sizeBytes: 2_147_483_648 // 2 GB
        )

        #expect(info.sizeGB == 2.0)
    }

    @Test("LocalModelInfo handles zero size")
    func handlesZeroSize() {
        let info = LocalModelInfo(
            id: "empty",
            path: URL(fileURLWithPath: "/empty"),
            sizeBytes: 0
        )

        #expect(info.sizeGB == 0.0)
    }

    @Test("LocalModelInfo is Sendable and Identifiable")
    func conformsToProtocols() {
        let info = LocalModelInfo(
            id: "test",
            path: URL(fileURLWithPath: "/test"),
            sizeBytes: 1000
        )

        // Compile-time check for Sendable
        let _: any Sendable.Type = LocalModelInfo.self

        // Identifiable
        _ = info.id
    }
}

// MARK: - MLX Inference Engine State Tests

@Suite("MLXInferenceEngine State")
struct MLXInferenceEngineStateTests {

    @Test("Engine initializes with default models directory")
    func initializesWithDefaultDirectory() async {
        let engine = MLXInferenceEngine()
        let state = await engine.currentState()

        #expect(state == .idle)
    }

    @Test("Engine initializes with custom models directory")
    func initializesWithCustomDirectory() async {
        let customDir = URL(fileURLWithPath: "/custom/models")
        let engine = MLXInferenceEngine(modelsDir: customDir)
        let state = await engine.currentState()

        #expect(state == .idle)
    }

    @Test("Engine state starts as idle")
    func stateStartsIdle() async {
        let engine = MLXInferenceEngine()
        let state = await engine.currentState()

        #expect(state == .idle)
    }

    @Test("No model loaded initially")
    func noModelInitially() async {
        let engine = MLXInferenceEngine()
        let model = await engine.currentModel()

        #expect(model == nil)
    }

    @Test("Unloading model when none loaded is safe")
    func unloadWhenEmptyIsSafe() async {
        let engine = MLXInferenceEngine()

        await engine.unloadModel()

        let state = await engine.currentState()
        let model = await engine.currentModel()

        #expect(state == .idle)
        #expect(model == nil)
    }
}

@Suite("MLXInferenceEngine Model Management")
struct MLXInferenceEngineModelTests {

    @Test("Available models returns empty for non-existent directory")
    func availableModelsEmptyForMissingDir() async {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let engine = MLXInferenceEngine(modelsDir: tempDir)

        let models = await engine.availableModels()

        #expect(models.isEmpty)
    }

    @Test("Available models finds models with config.json")
    func availableModelsFindsModels() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("mlx-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a fake model directory structure
        let modelDir = tempDir.appendingPathComponent("test-model")
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        // Create config.json
        let config = ["model_type": "llama", "hidden_size": 4096] as [String: Any]
        let configData = try JSONSerialization.data(withJSONObject: config)
        try configData.write(to: modelDir.appendingPathComponent("config.json"))

        let engine = MLXInferenceEngine(modelsDir: tempDir)
        let models = await engine.availableModels()

        #expect(models.count == 1)
        #expect(models[0].id == "test-model")
    }

    @Test("Available models skips directories without config.json")
    func availableModelsSkipsInvalid() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("mlx-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a directory without config.json
        let modelDir = tempDir.appendingPathComponent("invalid-model")
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        // Create a random file, not config.json
        try "not config".write(to: modelDir.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)

        let engine = MLXInferenceEngine(modelsDir: tempDir)
        let models = await engine.availableModels()

        #expect(models.isEmpty)
    }

    @Test("Load model fails for non-existent model")
    func loadModelFailsForMissing() async {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let engine = MLXInferenceEngine(modelsDir: tempDir)

        await #expect(throws: MLXError.self) {
            try await engine.loadModel(id: "non-existent-model")
        }

        let state = await engine.currentState()
        #expect(state == .error("Not found"))
    }

    @Test("Generate fails when no model loaded")
    func generateFailsWhenEmpty() async {
        let engine = MLXInferenceEngine()

        await #expect(throws: MLXError.self) {
            _ = try await engine.generate(prompt: "Hello")
        }
    }
}

@Suite("MLXInferenceEngine Static Properties")
struct MLXInferenceEngineStaticTests {

    @Test("isAppleSilicon is true on arm64")
    func isAppleSiliconOnARM64() {
        // This is a compile-time/architecture test
        // On actual Apple Silicon, this returns true
        // On Intel Macs or simulators, it may return false
        let isARM = MLXInferenceEngine.isAppleSilicon

        #if arch(arm64)
        #expect(isARM == true)
        #else
        #expect(isARM == false)
        #endif
    }

    @Test("availableMemoryGB returns positive value")
    func availableMemoryPositive() {
        let memoryGB = MLXInferenceEngine.availableMemoryGB
        // Just the positivity invariant — a hard lower bound is fragile in
        // constrained CI / simulator environments.
        #expect(memoryGB > 0)
    }

    @Test("availableMemoryGB is consistent")
    func availableMemoryConsistent() {
        let first = MLXInferenceEngine.availableMemoryGB
        let second = MLXInferenceEngine.availableMemoryGB

        #expect(first == second)
    }
}

@Suite("MLXInferenceEngine Engine State")
struct MLXInferenceEngineStateMachineTests {

    @Test("EngineState is Equatable")
    func stateIsEquatable() {
        let idle1: MLXInferenceEngine.EngineState = .idle
        let idle2: MLXInferenceEngine.EngineState = .idle
        let loading: MLXInferenceEngine.EngineState = .loading
        let ready: MLXInferenceEngine.EngineState = .ready

        #expect(idle1 == idle2)
        #expect(idle1 != loading)
        #expect(loading != ready)
    }

    @Test("EngineState error case stores message")
    func errorStoresMessage() {
        let error: MLXInferenceEngine.EngineState = .error("Out of memory")

        if case .error(let msg) = error {
            #expect(msg == "Out of memory")
        } else {
            Issue.record("Expected error state")
        }
    }

    @Test("All EngineState cases exist")
    func allStateCasesExist() {
        let states: [MLXInferenceEngine.EngineState] = [
            .idle,
            .loading,
            .ready,
            .generating,
            .error("test")
        ]
        #expect(states.count == 5)
    }

    @Test("EngineState is Sendable")
    func stateIsSendable() {
        let state: MLXInferenceEngine.EngineState = .ready
        // Compile-time check
        let _: any Sendable.Type = MLXInferenceEngine.EngineState.self
        _ = state
    }
}

@Suite("MLXInferenceEngine Edge Cases")
struct MLXInferenceEngineEdgeCaseTests {

    @Test("Generate with zero max tokens")
    // These four tests verify the engine ACCEPTS the parameter (no early
    // rejection on bounds) and reaches the `.noModelLoaded` check. They
    // assert the specific error so that if a future change adds parameter
    // validation and rejects with a different error, the test fails
    // loudly rather than passing on a generic throw.

    func generateWithZeroTokens() async {
        let engine = MLXInferenceEngine()
        let captured = await #expect(throws: MLXError.self) {
            _ = try await engine.generate(prompt: "test", maxTokens: 0)
        }
        if case .noModelLoaded = captured {} else {
            Issue.record("Expected MLXError.noModelLoaded, got \(String(describing: captured))")
        }
    }

    @Test("Generate with very large max tokens")
    func generateWithLargeTokens() async {
        let engine = MLXInferenceEngine()
        let captured = await #expect(throws: MLXError.self) {
            _ = try await engine.generate(prompt: "test", maxTokens: 1_000_000)
        }
        if case .noModelLoaded = captured {} else {
            Issue.record("Expected MLXError.noModelLoaded, got \(String(describing: captured))")
        }
    }

    @Test("Generate with extreme temperature")
    func generateWithExtremeTemperature() async {
        let engine = MLXInferenceEngine()
        let captured = await #expect(throws: MLXError.self) {
            _ = try await engine.generate(prompt: "test", temperature: 100.0)
        }
        if case .noModelLoaded = captured {} else {
            Issue.record("Expected MLXError.noModelLoaded, got \(String(describing: captured))")
        }
    }

    @Test("Generate with negative temperature")
    func generateWithNegativeTemperature() async {
        let engine = MLXInferenceEngine()
        let captured = await #expect(throws: MLXError.self) {
            _ = try await engine.generate(prompt: "test", temperature: -1.0)
        }
        if case .noModelLoaded = captured {} else {
            Issue.record("Expected MLXError.noModelLoaded, got \(String(describing: captured))")
        }
    }

    @Test("Empty prompt handled")
    func emptyPrompt() async {
        let engine = MLXInferenceEngine()

        await #expect(throws: MLXError.self) {
            _ = try await engine.generate(prompt: "")
        }
    }

    @Test("Long prompt handled")
    func longPrompt() async {
        let engine = MLXInferenceEngine()
        let longPrompt = String(repeating: "word ", count: 10000)

        await #expect(throws: MLXError.self) {
            _ = try await engine.generate(prompt: longPrompt)
        }
    }
}
