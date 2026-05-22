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

public actor FALClient {

    public typealias APIKeyProvider = @Sendable () async throws -> String

    public struct Config: Sendable {
        public let baseQueueURL: URL
        public let pollIntervalSeconds: Double
        public let maxPollAttempts: Int

        public init(
            baseQueueURL: URL = URL(string: "https://queue.fal.run")!,
            pollIntervalSeconds: Double = 2.0,
            maxPollAttempts: Int = 180  // ~6 minutes at 2s
        ) {
            self.baseQueueURL = baseQueueURL
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
        // Firewall: deny callers without `networkAccess`. Cheap actor lookup.
        if let firewall {
            do {
                try await firewall.require(.networkAccess)
            } catch {
                await audit(.toolCallDenied, "FAL submit denied: \(modelID)", success: false)
                throw error
            }
        }
        await audit(.toolCallStarted, "FAL submit: \(modelID)")

        let key: String
        do { key = try await apiKey() } catch {
            await audit(.toolCallFailed, "FAL submit: missing API key for \(modelID)", success: false)
            throw FALError.missingAPIKey
        }

        // Submit
        let submitURL = config.baseQueueURL.appendingPathComponent(modelID)
        var submitReq = URLRequest(url: submitURL)
        submitReq.httpMethod = "POST"
        submitReq.setValue("Key \(key)", forHTTPHeaderField: "Authorization")
        submitReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        submitReq.httpBody = payload
        let (submitData, submitResponse) = try await urlSession.data(for: submitReq)
        let submitHTTP = submitResponse as? HTTPURLResponse
        guard let code = submitHTTP?.statusCode, (200..<300).contains(code) else {
            let snippet = String(data: submitData, encoding: .utf8)?.prefix(200) ?? ""
            throw FALError.httpError(submitHTTP?.statusCode ?? -1, String(snippet))
        }
        let submitJSON = try JSONSerialization.jsonObject(with: submitData) as? [String: Any] ?? [:]
        guard let requestID = submitJSON["request_id"] as? String else {
            throw FALError.decodeError("No request_id in submit response")
        }

        // Poll status
        let statusURL = submitURL.appendingPathComponent("requests/\(requestID)/status")
        var statusReq = URLRequest(url: statusURL)
        statusReq.setValue("Key \(key)", forHTTPHeaderField: "Authorization")

        for _ in 0..<config.maxPollAttempts {
            let (statusData, statusResponse) = try await urlSession.data(for: statusReq)
            let statusHTTP = statusResponse as? HTTPURLResponse
            if let c = statusHTTP?.statusCode, !(200..<300).contains(c) {
                let snippet = String(data: statusData, encoding: .utf8)?.prefix(200) ?? ""
                throw FALError.httpError(c, String(snippet))
            }
            let statusJSON = try JSONSerialization.jsonObject(with: statusData) as? [String: Any] ?? [:]
            let status = (statusJSON["status"] as? String) ?? ""
            switch status {
            case "COMPLETED":
                // Fetch full response
                let resultURL = submitURL.appendingPathComponent("requests/\(requestID)")
                var resultReq = URLRequest(url: resultURL)
                resultReq.setValue("Key \(key)", forHTTPHeaderField: "Authorization")
                let (resultData, _) = try await urlSession.data(for: resultReq)
                await audit(.toolCallSucceeded, "FAL completed: \(modelID) req=\(requestID)")
                return resultData
            case "IN_QUEUE", "IN_PROGRESS":
                try await Task.sleep(nanoseconds: UInt64(config.pollIntervalSeconds * 1_000_000_000))
            default:
                let logs = (statusJSON["logs"] as? [[String: Any]])?.last?["message"] as? String
                await audit(.toolCallFailed, "FAL failed: \(modelID) status=\(status)", success: false)
                throw FALError.queueFailed(logs ?? "status=\(status)")
            }
        }
        await audit(.toolCallFailed, "FAL timeout: \(modelID)", success: false)
        throw FALError.queueTimeout
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
