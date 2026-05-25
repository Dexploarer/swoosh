// DetourPairingWebServer.swift — local install-aware pairing page server (0.5A)

import Foundation
@preconcurrency import Network

final class DetourPairingWebServer: @unchecked Sendable {
    static let shared = DetourPairingWebServer()

    private let queue = DispatchQueue(label: "ai.swoosh.detour.pairing-web")
    private var listener: NWListener?
    private var page: PairingPage?
    private let port: UInt16 = 8788

    private init() {}

    func pairingPageURL(ipAddress: String, daemonHost: String, token: String) throws -> URL {
        page = PairingPage(
            daemonHost: daemonHost,
            token: token,
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
            URLQueryItem(name: "token", value: token),
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
        let path = request
            .split(separator: "\r\n", maxSplits: 1)
            .first?
            .split(separator: " ")
            .dropFirst()
            .first
            .map(String.init) ?? "/"

        let body: String
        let status: String
        if path.hasPrefix("/pair"), let page {
            status = "200 OK"
            body = page.html
        } else if path.hasPrefix("/install"), let page {
            let result = DetourIOSInstaller.installOnFirstPairedIPhone()
            status = result.succeeded ? "200 OK" : "500 Internal Server Error"
            body = page.installResultHTML(result)
        } else if path.hasPrefix("/health") {
            status = "200 OK"
            body = "ok"
        } else {
            status = "404 Not Found"
            body = "not found"
        }

        let bodyData = Data(body.utf8)
        let contentType = body.contains("<!doctype html>") ? "text/html; charset=utf-8" : "text/plain; charset=utf-8"
        let head = [
            "HTTP/1.1 \(status)",
            "Content-Type: \(contentType)",
            "Content-Length: \(bodyData.count)",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        var response = Data(head.utf8)
        response.append(bodyData)
        return response
    }
}

private struct PairingPage {
    let daemonHost: String
    let token: String
    let minimumIOSVersion: String
    let installURL: String?

    var html: String {
        let externalInstallButton = sanitizedInstallURL().map {
            #"<a class="button secondary" href="\#(htmlEscape($0))">External Install</a>"#
        } ?? ""

        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Detour</title>
        <style>
        :root { color-scheme: dark; }
        body {
          margin: 0;
          min-height: 100vh;
          display: grid;
          place-items: center;
          background: #050505;
          color: #f4f4f3;
          font: 17px -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
        }
        main { width: min(88vw, 360px); text-align: center; }
        h1 { margin: 0 0 12px; font-size: 32px; letter-spacing: 0; }
        p { margin: 0 0 22px; color: #c6c6c3; line-height: 1.38; }
        .button {
          display: block;
          margin: 12px 0;
          padding: 15px 18px;
          border-radius: 8px;
          background: #b5522d;
          color: white;
          text-decoration: none;
          font-weight: 700;
        }
        .secondary { background: #f1f1ef; color: #0a0a0a; }
        </style>
        </head>
        <body>
        <main>
        <h1>Detour</h1>
        <p>Install Detour from this Mac, then open pairing.</p>
        <a class="button" href="/install">Install on iPhone</a>
        \(externalInstallButton)
        </main>
        </body>
        </html>
        """
    }

    func installResultHTML(_ result: DetourIOSInstallResult) -> String {
        let deepLink = pairingDeepLink()
        let action = result.succeeded
            ? #"<a class="button" href="\#(htmlEscape(deepLink))">Open Detour</a>"#
            : #"<a class="button" href="/install">Try Again</a>"#

        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Detour</title>
        <style>
        :root { color-scheme: dark; }
        body {
          margin: 0;
          min-height: 100vh;
          display: grid;
          place-items: center;
          background: #050505;
          color: #f4f4f3;
          font: 17px -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
        }
        main { width: min(88vw, 360px); text-align: center; }
        h1 { margin: 0 0 12px; font-size: 32px; letter-spacing: 0; }
        p { margin: 0 0 22px; color: #c6c6c3; line-height: 1.38; }
        .button {
          display: block;
          margin: 12px 0;
          padding: 15px 18px;
          border-radius: 8px;
          background: #b5522d;
          color: white;
          text-decoration: none;
          font-weight: 700;
        }
        </style>
        </head>
        <body>
        <main>
        <h1>\(htmlEscape(result.title))</h1>
        <p>\(htmlEscape(result.detail))</p>
        \(action)
        </main>
        </body>
        </html>
        """
    }

    private func pairingDeepLink() -> String {
        var components = URLComponents()
        components.scheme = "swoosh"
        components.host = "pair"
        components.queryItems = [
            URLQueryItem(name: "host", value: daemonHost),
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "app", value: DetourPairingSupport.iOSBundleIdentifier),
            URLQueryItem(name: "min_ios_version", value: minimumIOSVersion)
        ]
        return components.url?.absoluteString ?? ""
    }

    private func sanitizedInstallURL() -> String? {
        guard let value = installURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["https", "itms-apps", "itms-services"].contains(scheme) else {
            return nil
        }
        return value
    }
}

private func htmlEscape(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}
