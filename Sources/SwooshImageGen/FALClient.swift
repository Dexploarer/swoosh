// SwooshImageGen/FALClient.swift
// Version: 0.9R
//
// Minimal FAL.ai HTTP client. Handles the queue-based submission flow:
//   1. POST https://queue.fal.run/<model> { ...args }     → { request_id }
//   2. Poll https://queue.fal.run/<model>/requests/<id>/status until COMPLETED
//   3. GET   https://queue.fal.run/<model>/requests/<id>  → final response body
//
// Auth: Authorization: Key <FAL_KEY>. The key arrives through a closure
// so the module stays free of Keychain dependencies.
//
// Optional `firewall` + `auditLog` injections gate every network call
// behind `SwooshPermission.networkAccess` and emit `AuditEntry` records
// for submit / poll / fetch / download. When both are nil (the iOS
// picker path), behavior is unchanged.

import Foundation
import SwooshTools

private extension URL {
    static func staticURL(_ s: StaticString) -> URL {
        guard let url = URL(string: "\(s)") else { preconditionFailure("Invalid static URL: \(s)") }
        return url
    }
}

public actor FALClient {

    public typealias APIKeyProvider = @Sendable () async throws -> String

    public struct Config: Sendable {
        public let baseQueueURL: URL
        public let pollIntervalSeconds: Double
        public let maxPollAttempts: Int

        public init(
            baseQueueURL: URL? = nil,
            pollIntervalSeconds: Double = 2.0,
            maxPollAttempts: Int = 180  // ~6 minutes at 2s
        ) {
            self.baseQueueURL = baseQueueURL ?? .staticURL("https://queue.fal.run")
            self.pollIntervalSeconds = pollIntervalSeconds
            self.maxPollAttempts = maxPollAttempts
        }
    }

    public enum FALError: Error, CustomStringConvertible, Sendable {
        case missingAPIKey
        case httpError(Int, String)
        case decodeError(String)
        case queueTimeout
        case queueFailed(String)

        public var description: String {
            switch self {
            case .missingAPIKey:           return "Missing FAL_KEY."
            case .httpError(let c, let s): return "FAL HTTP \(c): \(s)"
            case .decodeError(let m):      return "FAL decode error: \(m)"
            case .queueTimeout:            return "FAL queue timed out."
            case .queueFailed(let m):      return "FAL queue failed: \(m)"
            }
        }
    }

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
            kind: kind, toolName: "fal-client", detail: detail, success: success
        ))
    }

    /// Submit a queued request and poll until COMPLETED. Returns the
    /// final response JSON body as raw bytes — caller parses out the
    /// model-specific fields (e.g. `video.url`, `model_mesh.url`).
    /// Raw Data avoids passing `[String: Any]` across the actor boundary.
    public func runQueued(modelID: String, payload: Data) async throws -> Data {
        try await requireNetwork(modelID: modelID)
        await audit(.toolCallStarted, "FAL submit: \(modelID)")
        let key = try await resolveKey(modelID: modelID)
        let submitURL = config.baseQueueURL.appendingPathComponent(modelID)
        let requestID = try await submit(payload: payload, to: submitURL, key: key)
        return try await pollUntilComplete(modelID: modelID, requestID: requestID, submitURL: submitURL, key: key)
    }

    private func requireNetwork(modelID: String) async throws {
        guard let firewall else { return }
        do {
            try await firewall.require(.networkAccess)
        } catch {
            await audit(.toolCallDenied, "FAL submit denied: \(modelID)", success: false)
            throw error
        }
    }

    private func resolveKey(modelID: String) async throws -> String {
        do { return try await apiKey() } catch {
            await audit(.toolCallFailed, "FAL submit: missing API key for \(modelID)", success: false)
            throw FALError.missingAPIKey
        }
    }

    private func submit(payload: Data, to submitURL: URL, key: String) async throws -> String {
        var req = URLRequest(url: submitURL)
        req.httpMethod = "POST"
        req.setValue("Key \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = payload
        let (data, response) = try await urlSession.data(for: req)
        try Self.ensureSuccess(data: data, response: response)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let requestID = json["request_id"] as? String else {
            throw FALError.decodeError("No request_id in submit response")
        }
        return requestID
    }

    private func pollUntilComplete(modelID: String, requestID: String, submitURL: URL, key: String) async throws -> Data {
        let statusURL = submitURL.appendingPathComponent("requests/\(requestID)/status")
        var statusReq = URLRequest(url: statusURL)
        statusReq.setValue("Key \(key)", forHTTPHeaderField: "Authorization")
        for _ in 0..<config.maxPollAttempts {
            let (data, response) = try await urlSession.data(for: statusReq)
            try Self.ensureSuccess(data: data, response: response)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            let status = (json["status"] as? String) ?? ""
            if status == "COMPLETED" {
                let result = try await fetchResult(submitURL: submitURL, requestID: requestID, key: key)
                await audit(.toolCallSucceeded, "FAL completed: \(modelID) req=\(requestID)")
                return result
            }
            if status == "IN_QUEUE" || status == "IN_PROGRESS" {
                try await Task.sleep(nanoseconds: UInt64(config.pollIntervalSeconds * 1_000_000_000))
                continue
            }
            let logs = (json["logs"] as? [[String: Any]])?.last?["message"] as? String
            await audit(.toolCallFailed, "FAL failed: \(modelID) status=\(status)", success: false)
            throw FALError.queueFailed(logs ?? "status=\(status)")
        }
        await audit(.toolCallFailed, "FAL timeout: \(modelID)", success: false)
        throw FALError.queueTimeout
    }

    private func fetchResult(submitURL: URL, requestID: String, key: String) async throws -> Data {
        var req = URLRequest(url: submitURL.appendingPathComponent("requests/\(requestID)"))
        req.setValue("Key \(key)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await urlSession.data(for: req)
        return data
    }

    private static func ensureSuccess(data: Data, response: URLResponse) throws {
        let http = response as? HTTPURLResponse
        guard let code = http?.statusCode, (200..<300).contains(code) else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw FALError.httpError(http?.statusCode ?? -1, String(snippet))
        }
    }

    /// Download bytes from a URL returned by FAL (signed CDN URLs).
    public func download(_ urlString: String) async throws -> Data {
        if let firewall {
            do {
                try await firewall.require(.networkAccess)
            } catch {
                await audit(.toolCallDenied, "FAL download denied: \(urlString)", success: false)
                throw error
            }
        }
        guard let url = URL(string: urlString) else {
            await audit(.toolCallFailed, "FAL download: invalid URL", success: false)
            throw FALError.decodeError("Invalid download URL: \(urlString)")
        }
        await audit(.toolCallStarted, "FAL download: \(url.host ?? "unknown-host")")
        let (data, response) = try await urlSession.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            await audit(.toolCallFailed, "FAL download: HTTP \(http.statusCode)", success: false)
            throw FALError.httpError(http.statusCode, "download")
        }
        await audit(.toolCallSucceeded, "FAL download: \(data.count) bytes")
        return data
    }
}
