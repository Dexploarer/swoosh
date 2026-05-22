// SwooshEmbeddings/LocalOpenAICompatibleEmbeddingProvider.swift
// Version: 0.9R
//
// Larger on-device embedding option for users who run Ollama / LM Studio
// / LocalAI / vLLM / llama.cpp-server on their Mac. Wire-compatible with
// the OpenAI /v1/embeddings endpoint — point this provider at
// http://127.0.0.1:11434/v1 (Ollama) or http://127.0.0.1:1234/v1 (LM
// Studio) and pick any embedding model the server hosts.
//
// Pairs well with:
//   • nomic-embed-text v1.5   — 768-dim, multilingual, Apache 2.0
//   • mxbai-embed-large-v1     — 1024-dim, English
//   • bge-m3                   — 1024-dim, multilingual
//   • snowflake-arctic-embed-l — Matryoshka, 256/512/768/1024-dim
//   • text-embedding-3-small   — when the local server proxies OpenAI
//
// Reports `isLocal == true` because the network call never leaves the
// machine (loopback or LAN host). Settings UI surfaces this as the
// "bigger local" choice next to the Apple NaturalLanguage default.

import Foundation

private extension URL {
    static func staticURL(_ s: StaticString) -> URL {
        guard let url = URL(string: "\(s)") else { preconditionFailure("Invalid static URL: \(s)") }
        return url
    }
}

public actor LocalOpenAICompatibleEmbeddingProvider: EmbeddingProviding {

    public struct Config: Sendable {
        public let baseURL: URL
        public let model: String
        public let outputDimension: Int
        public let providerID: String
        public let displayName: String

        public init(
            baseURL: URL,
            model: String,
            outputDimension: Int,
            providerID: String = "local-openai-embed",
            displayName: String = "Local OpenAI-compatible (on-device)"
        ) {
            self.baseURL = baseURL
            self.model = model
            self.outputDimension = outputDimension
            self.providerID = providerID
            self.displayName = displayName
        }

        /// Ollama default — assumes `ollama pull nomic-embed-text` has been run.
        public static let ollamaNomicEmbed = Config(
            baseURL: .staticURL("http://127.0.0.1:11434/v1"),
            model: "nomic-embed-text",
            outputDimension: 768,
            providerID: "ollama-nomic-embed",
            displayName: "Ollama · nomic-embed-text (on-device, 768-dim)"
        )

        /// Ollama mxbai-embed-large — `ollama pull mxbai-embed-large`.
        public static let ollamaMxbaiEmbed = Config(
            baseURL: .staticURL("http://127.0.0.1:11434/v1"),
            model: "mxbai-embed-large",
            outputDimension: 1024,
            providerID: "ollama-mxbai-embed",
            displayName: "Ollama · mxbai-embed-large (on-device, 1024-dim)"
        )

        /// Ollama bge-m3 — `ollama pull bge-m3`.
        public static let ollamaBGEM3 = Config(
            baseURL: .staticURL("http://127.0.0.1:11434/v1"),
            model: "bge-m3",
            outputDimension: 1024,
            providerID: "ollama-bge-m3",
            displayName: "Ollama · bge-m3 (on-device, 1024-dim, multilingual)"
        )

        /// LM Studio default — server runs on port 1234.
        public static func lmStudio(model: String, outputDimension: Int) -> Config {
            Config(
                baseURL: .staticURL("http://127.0.0.1:1234/v1"),
                model: model,
                outputDimension: outputDimension,
                providerID: "lmstudio-\(model)",
                displayName: "LM Studio · \(model) (on-device, \(outputDimension)-dim)"
            )
        }
    }

    private let config: Config
    private let urlSession: URLSession

    public init(config: Config = .ollamaNomicEmbed, urlSession: URLSession = .shared) {
        self.config = config
        self.urlSession = urlSession
    }

    public nonisolated var id: String { config.providerID }
    public nonisolated var displayName: String { config.displayName }
    public nonisolated var isLocal: Bool { true }

    public func dimension() async -> Int { config.outputDimension }

    public func embed(_ text: String) async throws -> [Float] {
        let vecs = try await embed([text])
        return vecs.first ?? []
    }

    public func embed(_ texts: [String]) async throws -> [[Float]] {
        let url = config.baseURL.appendingPathComponent("embeddings")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": config.model,
            "input": texts
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw EmbeddingProviderError.modelUnavailable(
                "Local embedding server at \(config.baseURL.absoluteString) is not reachable. Start Ollama or LM Studio, or fall back to the cloud provider."
            )
        }
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
