// SwooshMLX/MLXInferenceEngine.swift — Local inference via MLX
import Foundation

public actor MLXInferenceEngine {
    public enum EngineState: Sendable, Equatable {
        case idle, loading, ready, generating, error(String)
    }
    private var state: EngineState = .idle
    private var loadedModelID: String?
    private let modelsDir: URL

    public init(modelsDir: URL? = nil) {
        self.modelsDir = modelsDir ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".swoosh/models")
    }

    public func currentState() -> EngineState { state }
    public func currentModel() -> String? { loadedModelID }

    public func availableModels() -> [LocalModelInfo] {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: modelsDir, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { dir in
            let cfg = dir.appendingPathComponent("config.json")
            guard FileManager.default.fileExists(atPath: cfg.path) else { return nil }
            return LocalModelInfo(id: dir.lastPathComponent, path: dir, sizeBytes: 0)
        }
    }

    public func loadModel(id: String) async throws {
        state = .loading
        let path = modelsDir.appendingPathComponent(id)
        guard FileManager.default.fileExists(atPath: path.path) else {
            state = .error("Not found"); throw MLXError.modelNotFound(id)
        }
        loadedModelID = id; state = .ready
    }

    public func unloadModel() { loadedModelID = nil; state = .idle }

    public func generate(prompt: String, maxTokens: Int = 512, temperature: Double = 0.7) async throws -> String {
        guard state == .ready else { throw MLXError.noModelLoaded }
        state = .generating; defer { state = .ready }
        return "[MLX:\(loadedModelID ?? "?")] Local inference ready — pending MLXLLM integration"
    }

    public static var isAppleSilicon: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }
    public static var availableMemoryGB: Double { Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824 }
}

public struct LocalModelInfo: Sendable, Identifiable {
    public let id: String; public let path: URL; public let sizeBytes: UInt64
    public var sizeGB: Double { Double(sizeBytes) / 1_073_741_824 }
}

public enum MLXError: Error, Sendable {
    case modelNotFound(String), noModelLoaded, insufficientMemory(required: Double, available: Double)
}
