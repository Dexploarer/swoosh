// SwooshProviders/DetourCloudProvider.swift — 0.9P Detour Cloud provider
//
// Conservative implementation. Tests endpoints before claiming support.
// Auth key in Keychain only.
//
// $DTOUR integration: every API call includes the Swoosh affiliate code.
// Revenue (20% markup) accrues as $DTOUR tokens, swept to $DTOUR vault.

import Foundation
import SwooshSecrets
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Detour Cloud Provider
// ═══════════════════════════════════════════════════════════════════

public actor DetourCloudProvider: ModelProviding {
    public nonisolated let providerID: ProviderID = "detour-cloud"
    public nonisolated let displayName: String = "Detour Cloud"
    public nonisolated let capabilities = ProviderCapabilities(
        streaming: false, toolCalling: false, structuredOutput: false,
        embeddings: false, vision: false
    )

    private let secrets: any SecretStoring
    private let http: any HTTPClient
    private let baseURL: String

    public init(secrets: any SecretStoring, http: any HTTPClient = URLSessionHTTPClient(purpose: "provider:detour-cloud"),
                baseURL: String = "https://elizacloud.ai/api/v1") {
        self.secrets = secrets; self.http = http; self.baseURL = baseURL
    }

    // ── Complete ──────────────────────────────────────────────────

    public func complete(_ request: ModelRequest) async throws -> ModelResponse {
        let apiKey = try await loadAPIKey()

        // Try /responses first, fallback to /chat/completions
        do {
            return try await callResponses(apiKey: apiKey, request: request)
        } catch ProviderError.unsupportedEndpoint {
            return try await callChatCompletions(apiKey: apiKey, request: request)
        }
    }

    // ── Health ────────────────────────────────────────────────────

    public func health() async -> ProviderHealth {
        do {
            _ = try await loadAPIKey()
        } catch {
            return ProviderHealth(providerID: providerID, status: .authMissing,
                                  message: "Set key: swoosh provider auth detour-cloud --api-key")
        }

        // Probe /models
        do {
            let models = try await listModels()
            return ProviderHealth(providerID: providerID, status: .healthy,
                                  message: "\(models.count) models available")
        } catch {
            return ProviderHealth(providerID: providerID, status: .unreachable,
                                  message: "Cannot reach Detour Cloud: \(error.localizedDescription)")
        }
    }

    // ── Models ────────────────────────────────────────────────────

    public func listModels() async throws -> [String] {
        let apiKey = try await loadAPIKey()
        guard let url = URL(string: "\(baseURL)/models") else { return [] }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue(DtourAffiliateConfig.elizaAffiliateCode, forHTTPHeaderField: "X-Affiliate-Code")
        let response = try await http.send(req)

        guard let json = try JSONSerialization.jsonObject(with: response.data) as? [String: Any],
              let data = json["data"] as? [[String: Any]] else { return [] }
        return data.compactMap { $0["id"] as? String }
    }

    // ── Internals ─────────────────────────────────────────────────

    private func loadAPIKey() async throws -> String {
        do {
            return try await secrets.get(SecretRef("detour-cloud", "api_key"))
        } catch {
            throw ProviderError.authMissing(providerID,
                "Detour Cloud API key not found. Run: swoosh provider auth detour-cloud --api-key")
        }
    }

    private func callResponses(apiKey: String, request: ModelRequest) async throws -> ModelResponse {
        guard let url = URL(string: "\(baseURL)/responses") else {
            throw ProviderError.unsupportedEndpoint(providerID, "/responses")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(DtourAffiliateConfig.elizaAffiliateCode, forHTTPHeaderField: "X-Affiliate-Code")

        let body: [String: Any] = [
            "model": request.model,
            "input": request.messages.map { ["role": $0.role.rawValue, "content": $0.content] },
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let response = try await http.send(req)
            // Check for 404/405 = endpoint not supported
            if response.statusCode == 404 || response.statusCode == 405 {
                throw ProviderError.unsupportedEndpoint(providerID, "/responses")
            }
            guard let json = try JSONSerialization.jsonObject(with: response.data) as? [String: Any] else {
                throw ProviderError.responseParseFailed(providerID, "Invalid JSON")
            }

            // Parse Responses API format
            var text = ""
            if let output = json["output"] as? [[String: Any]] {
                for item in output {
                    if let content = item["content"] as? [[String: Any]] {
                        for part in content {
                            if part["type"] as? String == "output_text" {
                                text += (part["text"] as? String) ?? ""
                            }
                        }
                    }
                }
            }

            return ModelResponse(providerID: providerID, model: request.model,
                                 text: text, finishReason: "stop")
        } catch is HTTPError {
            throw ProviderError.unsupportedEndpoint(providerID, "/responses")
        }
    }

    private func callChatCompletions(apiKey: String, request: ModelRequest) async throws -> ModelResponse {
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw ProviderError.unsupportedEndpoint(providerID, "/chat/completions")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(DtourAffiliateConfig.elizaAffiliateCode, forHTTPHeaderField: "X-Affiliate-Code")

        let body: [String: Any] = [
            "model": request.model,
            "messages": request.messages.map { ["role": $0.role.rawValue, "content": $0.content] },
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let response = try await http.send(req)

        guard let json = try JSONSerialization.jsonObject(with: response.data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any] else {
            throw ProviderError.responseParseFailed(providerID, "Invalid chat completions response")
        }

        return ModelResponse(
            providerID: providerID, model: request.model,
            text: (message["content"] as? String) ?? "", finishReason: "stop"
        )
    }
}
