// SwooshToolsets/JSONRPCTransport.swift — JSON-RPC 2.0 over HTTP — 0.9R
//
// A small URLSession-backed JSON-RPC 2.0 client. Shared by the concrete
// EVM and Solana RPC clients. The `URLSession` is injectable so tests
// can drive it through `MockURLProtocol` with zero live network.

import Foundation
import SwooshTools

/// A decoded JSON-RPC 2.0 error object.
struct JSONRPCError: Error, Sendable {
    let code: Int
    let message: String
    var localizedDescription: String { "JSON-RPC error \(code): \(message)" }
}

/// URLSession-backed JSON-RPC 2.0 transport.
struct JSONRPCTransport: Sendable {
    let session: URLSession
    let requestTimeout: TimeInterval

    init(session: URLSession = .shared, requestTimeout: TimeInterval = 20) {
        self.session = session
        self.requestTimeout = requestTimeout
    }

    /// Perform a single JSON-RPC 2.0 call and return the raw `result`
    /// value as a `JSONSerialization` object (`Any`).
    ///
    /// - Throws: `JSONRPCError` for protocol-level errors, `ToolError`
    ///   for transport / decoding failures.
    func call(url: URL, method: String, params: [Any]) async throws -> Any {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Use a UUID string for the JSON-RPC id so concurrent calls on
        // the same transport never collide — JSON-RPC 2.0 allows string ids.
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": UUID().uuidString,
            "method": method,
            "params": params,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ToolError.executionFailed("RPC transport error for \(method): \(error.localizedDescription)")
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let snippet = String(data: data.prefix(256), encoding: .utf8) ?? ""
            throw ToolError.executionFailed("RPC HTTP \(http.statusCode) for \(method): \(snippet)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ToolError.executionFailed("RPC response for \(method) was not a JSON object")
        }

        if let errorObj = json["error"] as? [String: Any] {
            let code = (errorObj["code"] as? Int) ?? -1
            let message = (errorObj["message"] as? String) ?? "unknown error"
            throw JSONRPCError(code: code, message: message)
        }

        guard json.keys.contains("result") else {
            throw ToolError.executionFailed("RPC response for \(method) had neither result nor error")
        }
        // `result` may legitimately be NSNull (e.g. getTransactionReceipt
        // for an unmined hash) — return it as-is so callers can branch.
        return json["result"] ?? NSNull()
    }
}
