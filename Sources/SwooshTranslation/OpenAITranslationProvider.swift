// SwooshTranslation/OpenAITranslationProvider.swift
// Version: 0.9R
//
// Cloud fallback. Uses OpenAI's Responses API (or any OpenAI-compatible
// endpoint) to translate text when Apple Translation is unavailable.
// Routed by TranslationRouter — never called directly from tools.

import Foundation

public actor OpenAITranslationProvider: TranslationProviding {

    public struct Config: Sendable {
        public let baseURL: URL
        public let model: String
        public init(baseURL: URL = URL(string: "https://api.openai.com/v1")!, model: String = "gpt-4o-mini") {
            self.baseURL = baseURL; self.model = model
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

    public nonisolated var id: String { "openai-translation" }
    public nonisolated var displayName: String { "OpenAI (cloud)" }
    public nonisolated var isLocal: Bool { false }

    public func supportedLanguagePairs() async -> [TranslationLanguagePair] { [] }

    public func translate(_ text: String, from source: String?, to target: String) async throws -> String {
        let key: String
        do {
            key = try await apiKey()
        } catch {
            throw TranslationProviderError.missingAPIKey("openai")
        }
        let prompt = makePrompt(text: text, source: source, target: target)
        let url = config.baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": "You are a precise translator. Reply ONLY with the translated text."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.0
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranslationProviderError.requestFailed("No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw TranslationProviderError.requestFailed("HTTP \(http.statusCode): \(snippet)")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let choices = json["choices"] as? [[String: Any]] ?? []
        let message = choices.first?["message"] as? [String: Any]
        let content = message?["content"] as? String ?? ""
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranslationProviderError.requestFailed("Empty response from model")
        }
        return trimmed
    }

    private func makePrompt(text: String, source: String?, target: String) -> String {
        if let source {
            return "Translate the following text from \(source) to \(target):\n\n\(text)"
        }
        return "Translate the following text to \(target):\n\n\(text)"
    }
}
