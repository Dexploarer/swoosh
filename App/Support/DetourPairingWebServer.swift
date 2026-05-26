// DetourPairingWebServer.swift — local install-aware pairing page server (0.5A)

import Foundation
@preconcurrency import Network

final class DetourPairingWebServer: @unchecked Sendable {
    static let shared = DetourPairingWebServer()

    private let queue = DispatchQueue(label: "ai.swoosh.detour.pairing-web")
    private var listener: NWListener?
    private var page: PairingPage?
    private let port: UInt16 = 8788
    var onDevicePaired: (@Sendable (DetourPairingEvent) -> Void)?

    private init() {}

    func pairingPageURL(
        ipAddress: String,
        daemonHost: String,
        pairingNonce: String,
        confirmationCode: String,
        expiresAt: Date,
        setupBundle: DetourSetupTransferBundle
    ) throws -> URL {
        let callbackURL = "http://\(ipAddress):\(port)/paired?pairing=\(urlQueryEscape(pairingNonce))"
        let setupURL = "http://\(ipAddress):\(port)/setup?pairing=\(urlQueryEscape(pairingNonce))&code=\(urlQueryEscape(confirmationCode))"
        page = PairingPage(
            daemonHost: daemonHost,
            pairingNonce: pairingNonce,
            confirmationCode: confirmationCode,
            expiresAt: expiresAt,
            setupBundle: setupBundle,
            callbackURL: callbackURL,
            setupURL: setupURL,
            minimumIOSVersion: DetourPairingSupport.requiredIOSAppVersion,
            installURL: ProcessInfo.processInfo.environment["DETOUR_IOS_INSTALL_URL"]
        )
        try startIfNeeded()

        var components = URLComponents()
        components.scheme = "http"
        components.host = ipAddress
        components.port = Int(port)
        components.path = "/pair"
        components.queryItems = [
            URLQueryItem(name: "host", value: daemonHost),
            URLQueryItem(name: "pairing", value: pairingNonce),
            URLQueryItem(name: "callback", value: callbackURL),
            URLQueryItem(name: "setup_url", value: setupURL),
            URLQueryItem(name: "code", value: confirmationCode),
            URLQueryItem(name: "app", value: DetourPairingSupport.iOSBundleIdentifier),
            URLQueryItem(name: "min_ios_version", value: DetourPairingSupport.requiredIOSAppVersion)
        ]

        guard let url = components.url else {
            throw DetourPairingError.payloadEncodingFailed
        }
        return url
    }

    private func startIfNeeded() throws {
        guard listener == nil else { return }
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw DetourPairingError.pairingServerFailed
        }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.includePeerToPeer = true
        let listener = try NWListener(using: parameters, on: endpointPort)
        listener.service = NWListener.Service(
            name: ProcessInfo.processInfo.hostName,
            type: "_swoosh._tcp"
        )
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }
            let response = httpResponse(for: data)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func httpResponse(for data: Data?) -> Data {
        let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let requestTarget = request
            .split(separator: "\r\n", maxSplits: 1)
            .first?
            .split(separator: " ")
            .dropFirst()
            .first
            .map(String.init) ?? "/"
        let requestURL = URLComponents(string: "http://detour.local\(requestTarget)")
        let path = requestURL?.path ?? requestTarget
        let queryItems = requestURL?.queryItems ?? []

        let reply: HTTPReply
        if path.hasPrefix("/setup"), let page, page.isAuthorized(queryItems), page.hasConfirmation(queryItems) {
            if let setupData = try? page.setupData() {
                reply = HTTPReply(status: "200 OK", body: setupData, contentType: "application/json; charset=utf-8")
            } else {
                reply = HTTPReply(
                    status: "409 Conflict",
                    body: Data(#"{"ok":false,"error":"confirm pairing on the Mac first"}"#.utf8),
                    contentType: "application/json; charset=utf-8"
                )
            }
        } else if path.hasPrefix("/paired"), let page, page.isAuthorized(queryItems), page.hasConfirmation(queryItems) {
            let event = pairingEvent(from: queryItems)
            do {
                let label = event.platform == "unknown" ? event.deviceName : "\(event.deviceName) (\(event.platform))"
                try page.confirm(deviceName: label)
                onDevicePaired?(event)
                reply = HTTPReply(status: "200 OK", body: Data(#"{"ok":true}"#.utf8), contentType: "application/json; charset=utf-8")
            } catch {
                reply = HTTPReply(
                    status: "500 Internal Server Error",
                    body: Data(#"{"ok":false,"error":"could not issue paired device token"}"#.utf8),
                    contentType: "application/json; charset=utf-8"
                )
            }
        } else if path == "/pair", let page, page.isAuthorized(queryItems) {
            reply = HTTPReply(status: "200 OK", body: Data(page.html.utf8), contentType: "text/html; charset=utf-8")
        } else if path.hasPrefix("/install"), let page, page.isAuthorized(queryItems) {
            let result = DetourIOSInstaller.installOnFirstPairedIPhone()
            reply = HTTPReply(
                status: result.succeeded ? "200 OK" : "500 Internal Server Error",
                body: Data(page.installResultHTML(result).utf8),
                contentType: "text/html; charset=utf-8"
            )
        } else if path.hasPrefix("/health") {
            reply = HTTPReply(status: "200 OK", body: Data("ok".utf8), contentType: "text/plain; charset=utf-8")
        } else {
            reply = HTTPReply(status: "404 Not Found", body: Data("not found".utf8), contentType: "text/plain; charset=utf-8")
        }

        let head = [
            "HTTP/1.1 \(reply.status)",
            "Content-Type: \(reply.contentType)",
            "Content-Length: \(reply.body.count)",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        var response = Data(head.utf8)
        response.append(reply.body)
        return response
    }

    private func pairingEvent(from queryItems: [URLQueryItem]) -> DetourPairingEvent {
        let setup = queryItems.first(where: { $0.name == "setup" })?.value
            .flatMap { try? DetourSetupTransferBundle.decodeURLPayload($0) }
        return DetourPairingEvent(
            deviceName: queryItems.first(where: { $0.name == "device" })?.value ?? "Apple device",
            platform: queryItems.first(where: { $0.name == "platform" })?.value ?? "unknown",
            setupBundle: setup,
            pairedAt: .now
        )
    }

}

struct DetourPairingEvent: Equatable, Sendable {
    var deviceName: String
    var platform: String
    var setupBundle: DetourSetupTransferBundle?
    var pairedAt: Date
}

private struct HTTPReply {
    var status: String
    var body: Data
    var contentType: String
}
