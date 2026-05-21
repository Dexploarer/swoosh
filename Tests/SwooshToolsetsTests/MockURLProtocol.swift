// Tests/SwooshToolsetsTests/MockURLProtocol.swift
//
// Same pattern as Tests/SwooshActantBackendTests/MockURLProtocol.swift —
// a URLProtocol that serves canned responses so RPC-client tests never
// touch the live network. A cross-suite mutex keeps the static handler
// state race-free.

import Foundation

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) -> (Int, [String: String], Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _handler: Handler?

    static func with<R: Sendable>(
        _ handler: @escaping Handler,
        body: @Sendable () async throws -> R
    ) async throws -> R {
        await Mutex.shared.acquire()
        lock.withLock { _handler = handler }
        // Order matters: clear the handler BEFORE releasing the mutex.
        // The next waiter wakes on `release()`, then sets its own handler.
        // If we released before clearing, the next test could observe (or
        // have its handler overwritten by) the prior teardown.
        do {
            let result = try await body()
            lock.withLock { _handler = nil }
            await Mutex.shared.release()
            return result
        } catch {
            lock.withLock { _handler = nil }
            await Mutex.shared.release()
            throw error
        }
    }

    static func makeSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: cfg)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let handler = Self.lock.withLock { Self._handler }
        guard let handler else {
            client?.urlProtocol(self, didFailWithError: NSError(
                domain: "MockURLProtocol", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "no handler set"]
            ))
            return
        }
        let (status, headers, body) = handler(request)
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url, statusCode: status,
                  httpVersion: "HTTP/1.1", headerFields: headers
              ) else {
            client?.urlProtocol(self, didFailWithError: NSError(
                domain: "MockURLProtocol", code: -2,
                userInfo: [NSLocalizedDescriptionKey: "invalid request URL or response parameters"]
            ))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private actor Mutex {
    static let shared = Mutex()
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !locked { locked = true; return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            waiters.append(c)
        }
    }
    func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            locked = false
        }
    }
}

extension URLRequest {
    func bodyData() -> Data {
        if let body = httpBody { return body }
        guard let stream = httpBodyStream else { return Data() }
        var data = Data()
        stream.open(); defer { stream.close() }
        var buf = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buf, maxLength: buf.count)
            if n <= 0 { break }
            data.append(buf, count: n)
        }
        return data
    }
}
