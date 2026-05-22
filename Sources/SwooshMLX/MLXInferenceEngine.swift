// SwooshMLX/MLXInferenceEngine.swift — Local inference via MLX
import Foundation
import HFAPI
import MLXLLM
import MLXLMCommon
import MLXLMTokenizers
import MLXVLM

public actor MLXInferenceEngine {
    public enum EngineState: Sendable, Equatable {
        case idle, loading, ready, generating, error(String)
    }
    private var state: EngineState = .idle
    private var loadedModelID: String?
    private var container: ModelContainer?
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
        do {
            if FileManager.default.fileExists(atPath: path.path) {
                container = try await loadModelContainer(
                    from: path,
                    using: TokenizersLoader()
                )
            } else if Self.isMLXHubID(id) {
                container = try await loadModelContainer(
                    from: HubDownloader(),
                    using: TokenizersLoader(),
                    id: id
                )
            } else {
                state = .error("Not found")
                throw MLXError.modelNotFound(id)
            }
            loadedModelID = id
            state = .ready
        } catch let error as MLXError {
            throw error
        } catch {
            state = .error(error.localizedDescription)
            throw MLXError.loadFailed(id, error.localizedDescription)
        }
    }

    private static func isMLXHubID(_ id: String) -> Bool {
        id.hasPrefix("mlx-community/") || id.hasPrefix("mlx-org/")
    }

    public func unloadModel() { loadedModelID = nil; container = nil; state = .idle }

    public func generate(prompt: String, maxTokens: Int = 512, temperature: Double = 0.7) async throws -> String {
        guard state == .ready, let container else { throw MLXError.noModelLoaded }
        state = .generating; defer { state = .ready }
        let session = ChatSession(
            container,
            generateParameters: GenerateParameters(
                maxTokens: maxTokens,
                temperature: Float(temperature)
            )
        )
        return try await session.respond(to: prompt)
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
    case modelNotFound(String)
    case noModelLoaded
    case loadFailed(String, String)
    case insufficientMemory(required: Double, available: Double)
}

private struct HubDownloader: Downloader {
    private let client: HubClient

    init(client: HubClient = .default) {
        self.client = client
    }

    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        guard let repoID = Repo.ID(rawValue: id) else {
            throw HubDownloaderError.invalidRepositoryID(id)
        }
        let revision = revision ?? "main"
        if !useLatest,
           let cached = client.resolveCachedSnapshot(
            repo: repoID,
            revision: revision,
            matching: patterns
           ) {
            return cached
        }
        return try await client.downloadSnapshot(
            of: repoID,
            revision: revision,
            matching: patterns,
            progressHandler: progressHandler
        )
    }
}

private enum HubDownloaderError: LocalizedError {
    case invalidRepositoryID(String)

    var errorDescription: String? {
        switch self {
        case .invalidRepositoryID(let id):
            return "Invalid Hugging Face repository ID: \(id)"
        }
    }
}
