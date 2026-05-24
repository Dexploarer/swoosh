// SwooshWallet/RPCClient.swift — Single-endpoint JSON-RPC client — 0.9A
//
// One actor per (URL, chain). Holds a URLSession and serializes outbound
// JSON-RPC envelopes. The wallet UI never talks to the daemon to fetch
// balances — the phone hits public RPCs directly so balance reads work
// even when swooshd is offline.
//
// Robustness: requests are bounded by a 15 s timeout, non-2xx HTTP
// responses are surfaced as `RPCError.httpStatus` (not silently parsed as
// JSON-RPC, which used to throw a misleading `decode` error when a
// rate-limited endpoint returned an HTML 429 body). The orchestrator that
// composes a primary client with an ordered list of fallbacks lives in
// `MultiEndpointRPC.swift`.

import Foundation
import os

private let rpcLog = Logger(subsystem: "ai.swoosh", category: "wallet.rpc")

public actor RPCClient {
    public let url: URL
    private let session: URLSession
    private let timeoutSeconds: TimeInterval
    private var nextID: Int = 1

    public init(
        url: URL,
        session: URLSession = .shared,
        timeoutSeconds: TimeInterval = 15
    ) {
        self.url = url
        self.session = session
        self.timeoutSeconds = timeoutSeconds
    }

    public func call<T: Decodable>(
        _ method: String,
        params: [JSONValue],
        as: T.Type = T.self
    ) async throws -> T {
        let id = nextID
        nextID += 1

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeoutSeconds

        let envelope = JSONRPCRequest(id: id, method: method, params: params)
        do {
            request.httpBody = try JSONEncoder().encode(envelope)
        } catch {
            throw RPCError.transport("encode failed: \(error)")
        }

        let started = Date()
        let data: Data
        let response: URLResponse
        do {
            let pair = try await session.data(for: request)
            data = pair.0
            response = pair.1
        } catch {
            rpcLog.error("transport \(self.url.host ?? "?", privacy: .public) \(method, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw RPCError.transport(error.localizedDescription)
        }
        let elapsed = Date().timeIntervalSince(started)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data.prefix(256), encoding: .utf8) ?? "<binary>"
            rpcLog.error("\(self.url.host ?? "?", privacy: .public) \(method, privacy: .public) HTTP \(http.statusCode) (\(String(format: "%.2f", elapsed)) s)")
            throw RPCError.httpStatus(http.statusCode, body: body)
        }

        let decoded: JSONRPCResponse<T>
        do {
            decoded = try JSONDecoder().decode(JSONRPCResponse<T>.self, from: data)
        } catch {
            let body = String(data: data.prefix(256), encoding: .utf8) ?? "<binary>"
            rpcLog.error("\(self.url.host ?? "?", privacy: .public) \(method, privacy: .public) decode failed: \(body, privacy: .public)")
            throw RPCError.decode("\(error) — body: \(body)")
        }

        if let err = decoded.error {
            throw RPCError.rpc(code: err.code, message: err.message)
        }
        guard let result = decoded.result else {
            throw RPCError.unexpectedResponse("missing result")
        }
        rpcLog.debug("\(self.url.host ?? "?", privacy: .public) \(method, privacy: .public) ok (\(String(format: "%.2f", elapsed)) s)")
        return result
    }
}
