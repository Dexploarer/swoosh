// SwooshImageGen/OpenAIImageProvider.swift
// Version: 0.9R
//
// Cloud fallback. OpenAI Images API (gpt-image-1 / dall-e-3) for when
// Image Playground is unavailable or the caller wants photorealistic
// output. The API key arrives through a closure so the module stays
// free of Keychain dependencies.
//
// Optional `firewall` + `auditLog` enforce `.imageGenerate` permission
// and emit `AuditEntry` records around every generation request.

import Foundation
import SwooshTools

private extension URL {
    static func staticURL(_ s: StaticString) -> URL {
        guard let url = URL(string: "\(s)") else { preconditionFailure("Invalid static URL: \(s)") }
        return url
    }
}

public actor OpenAIImageProvider: ImageGenProviding {

    public struct Config: Sendable {
        public let baseURL: URL
        public let model: String
        public init(baseURL: URL? = nil, model: String = "gpt-image-1") {
            self.baseURL = baseURL ?? .staticURL("https://api.openai.com/v1")
            self.model = model
        }
    }

    public typealias APIKeyProvider = @Sendable () async throws -> String

    private let config: Config
    private let apiKey: APIKeyProvider
    private let urlSession: URLSession
    private let firewall: (any Firewall)?
    private let auditLog: (any AuditLogging)?

    public init(
        config: Config = Config(),
        apiKey: @escaping APIKeyProvider,
        urlSession: URLSession = .shared,
        firewall: (any Firewall)? = nil,
        auditLog: (any AuditLogging)? = nil
    ) {
        self.config = config
        self.apiKey = apiKey
        self.urlSession = urlSession
        self.firewall = firewall
        self.auditLog = auditLog
    }

    private func audit(_ kind: AuditEntryKind, _ detail: String, success: Bool = true) async {
        guard let auditLog else { return }
        try? await auditLog.append(AuditEntry(
            kind: kind, toolName: id, detail: detail, success: success
        ))
    }

    public nonisolated var id: String { "openai-image" }
    public nonisolated var displayName: String { "OpenAI Image (cloud)" }
    public nonisolated var isLocal: Bool { false }
    public nonisolated var supportsCustomSize: Bool { true }

    public func supportedStyles() async -> [ImageGenStyle] {
        [
            ImageGenStyle(id: "natural", displayName: "Natural"),
            ImageGenStyle(id: "vivid",   displayName: "Vivid"),
        ]
    }

    public func generate(_ request: ImageGenRequest) async throws -> ImageGenResult {
        try await requirePermission()
        await auditStart(request)
        let key = try await resolveKey()
        let req = try buildRequest(for: request, key: key)
        let data = try await sendRequest(req)
        let png = try await parseImage(from: data)
        await audit(.toolCallSucceeded, "bytes=\(png.count)")
        return ImageGenResult(pngData: png, providerID: id, usedStyle: request.style?.id)
    }

    private func requirePermission() async throws {
        guard let firewall else { return }
        do {
            try await firewall.require(.imageGenerate)
        } catch {
            await audit(.toolCallDenied, "denied", success: false)
            throw error
        }
    }

    private func auditStart(_ request: ImageGenRequest) async {
        let promptHash = String(request.prompt.hash, radix: 16)
        let style = request.style?.id ?? "default"
        await audit(
            .toolCallStarted,
            "model=\(config.model) size=\(request.width)x\(request.height) promptHash=\(promptHash) style=\(style)"
        )
    }

    private func resolveKey() async throws -> String {
        do {
            return try await apiKey()
        } catch {
            await audit(.toolCallFailed, "missing API key", success: false)
            throw ImageGenError.missingAPIKey("openai")
        }
    }

    private func buildRequest(for request: ImageGenRequest, key: String) throws -> URLRequest {
        let url = config.baseURL.appendingPathComponent("images/generations")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "model": config.model,
            "prompt": request.prompt,
            "n": 1,
            "size": "\(request.width)x\(request.height)",
            "response_format": "b64_json"
        ]
        if let style = request.style { body["style"] = style.id }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    private func sendRequest(_ req: URLRequest) async throws -> Data {
        let (data, response) = try await urlSession.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            await audit(.toolCallFailed, "no HTTP response", success: false)
            throw ImageGenError.generationFailed("No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            await audit(.toolCallFailed, "HTTP \(http.statusCode)", success: false)
            throw ImageGenError.generationFailed("HTTP \(http.statusCode): \(Self.safeErrorSnippet(data))")
        }
        return data
    }

    private func parseImage(from data: Data) async throws -> Data {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let images = json["data"] as? [[String: Any]] ?? []
        guard let first = images.first,
              let b64 = first["b64_json"] as? String,
              let png = Data(base64Encoded: b64) else {
            await audit(.toolCallFailed, "unexpected response shape", success: false)
            throw ImageGenError.generationFailed("Unexpected response shape")
        }
        return png
    }

    /// Truncate to 50 chars, collapse whitespace, and redact common secret
    /// fragments so an upstream error body never carries an inline API key
    /// or token into our logs. Lossy by design.
    private static func safeErrorSnippet(_ data: Data) -> String {
        var text = String(data: data, encoding: .utf8) ?? ""
        let secretFragments = ["sk_", "Bearer ", "api_key", "apiKey", "token", "Authorization"]
        for fragment in secretFragments where text.contains(fragment) {
            text = text.replacingOccurrences(of: fragment, with: "[redacted]")
        }
        text = text.replacingOccurrences(of: "\n", with: " ")
        text = text.replacingOccurrences(of: "\r", with: " ")
        if text.count > 50 { text = String(text.prefix(49)) + "…" }
        return text
    }
}
