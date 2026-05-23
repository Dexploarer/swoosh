// SwooshEmbeddings/OpenAIEmbeddingProvider.swift
// Version: 0.9R
//
// Cloud fallback. POST /v1/embeddings on any OpenAI-compatible endpoint.
// Default model is text-embedding-3-small (1536 dim).

import Foundation

public actor OpenAIEmbeddingProvider: EmbeddingProviding {

    public struct Config: Sendable {
        public let baseURL: URL
        public let model: String
        public let outputDimension: Int
        public init(
            baseURL: URL = URL(string: "https://api.openai.com/v1")!,
            model: String = "text-embedding-3-small",
            outputDimension: Int = 1536
        ) {
            self.baseURL = baseURL; self.model = model; self.outputDimension = outputDimension
        }
    }

    public typealias APIKeyProvider = @Sendable () async throws -> String

    private let config: Config
    private let apiKey: APIKeyProvider
    private let urlSession: URLSession

    public init(config: Config = Config(), apiKey: @escaping APIKeyProvider, urlSession: URLSession = .shared) {
        self.config = config
        self.apiKey = apiKey
        self.urlSession = urlSession
    }

    public nonisolated var id: String { "openai-embed" }
    public nonisolated var displayName: String { "OpenAI Embeddings (cloud)" }
    public nonisolated var isLocal: Bool { false }

    public func dimension() async -> Int { config.outputDimension }

    public func embed(_ text: String) async throws -> [Float] {
        let vecs = try await embed([text])
        guard let first = vecs.first else {
            throw EmbeddingProviderError.requestFailed(
                "OpenAI embed response was empty — expected at least one vector"
            )
        }
        return first
    }

    public func embed(_ texts: [String]) async throws -> [[Float]] {
        let key: String
        do {
            key = try await apiKey()
        } catch {
            throw EmbeddingProviderError.missingAPIKey("openai")
        }
        let url = config.baseURL.appendingPathComponent("embeddings")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": config.model,
            "input": texts
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw EmbeddingProviderError.requestFailed("No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw EmbeddingProviderError.requestFailed("HTTP \(http.statusCode): \(snippet)")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let dataArray = json["data"] as? [[String: Any]] ?? []
        let vectors: [[Float]] = dataArray.compactMap { entry in
            guard let arr = entry["embedding"] as? [Double] else { return nil }
            return arr.map { Float($0) }
        }
        guard vectors.count == texts.count else {
            throw EmbeddingProviderError.requestFailed("Expected \(texts.count) vectors, got \(vectors.count)")
        }
        return vectors
    }
}
