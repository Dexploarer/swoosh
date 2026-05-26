// DetourPairingPage.swift — confirmed pairing page payload state (0.5A)

import Foundation

final class PairingPage: @unchecked Sendable {
    let daemonHost: String
    let pairingNonce: String
    let confirmationCode: String
    let expiresAt: Date
    let callbackURL: String
    let setupURL: String
    let minimumIOSVersion: String
    let installURL: String?

    private let setupBundle: DetourSetupTransferBundle
    private var confirmedToken: String?
    private var confirmedTokenExpiresAt: Date?

    init(
        daemonHost: String,
        pairingNonce: String,
        confirmationCode: String,
        expiresAt: Date,
        setupBundle: DetourSetupTransferBundle,
        callbackURL: String,
        setupURL: String,
        minimumIOSVersion: String,
        installURL: String?
    ) {
        self.daemonHost = daemonHost
        self.pairingNonce = pairingNonce
        self.confirmationCode = confirmationCode
        self.expiresAt = expiresAt
        self.setupBundle = setupBundle
        self.callbackURL = callbackURL
        self.setupURL = setupURL
        self.minimumIOSVersion = minimumIOSVersion
        self.installURL = installURL
    }

    func confirm(deviceName: String, ttl: TimeInterval = 30 * 24 * 60 * 60) throws {
        guard confirmedToken == nil else { return }
        let token = try DetourPairingSupport.mintPairedDeviceToken()
        let tokenExpiresAt = Date().addingTimeInterval(ttl)
        try DetourPairingSupport.persistPairedAPIToken(
            token,
            label: deviceName,
            expiresAt: tokenExpiresAt
        )
        confirmedToken = token
        confirmedTokenExpiresAt = tokenExpiresAt
    }

    func setupData() throws -> Data? {
        guard let token = confirmedToken,
              let tokenExpiresAt = confirmedTokenExpiresAt else {
            return nil
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(DetourPairingSetupEnvelope(
            schemaVersion: 1,
            host: daemonHost,
            apiToken: token,
            pairedTokenExpiresAt: tokenExpiresAt,
            setupBundle: setupBundle,
            confirmationCode: confirmationCode,
            issuedAt: .now,
            expiresAt: expiresAt
        ))
    }

    var html: String {
        let externalInstallButton = sanitizedInstallURL().map {
            #"<a class="button secondary" href="\#(htmlEscape($0))">External Install</a>"#
        } ?? ""
        let installPath = "/install?pairing=\(urlQueryEscape(pairingNonce))"
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Detour</title>
        <style>\(Self.css)</style>
        </head>
        <body>
        <main>
        <h1>Detour</h1>
        <p>Open Detour. Confirm code \(htmlEscape(confirmationCode)) on your Mac if prompted.</p>
        <a class="button" href="\(htmlEscape(pairingDeepLink()))">Open Detour</a>
        <a class="button" href="\(installPath)">Install on iPhone</a>
        \(externalInstallButton)
        </main>
        </body>
        </html>
        """
    }

    func installResultHTML(_ result: DetourIOSInstallResult) -> String {
        let action = result.succeeded
            ? #"<a class="button" href="\#(htmlEscape(pairingDeepLink()))">Open Detour</a>"#
            : #"<a class="button" href="/install?pairing=\#(urlQueryEscape(pairingNonce))">Try Again</a>"#
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Detour</title>
        <style>\(Self.css)</style>
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

    func isAuthorized(_ queryItems: [URLQueryItem]) -> Bool {
        guard expiresAt > .now,
              let candidate = queryItems.first(where: { $0.name == "pairing" || $0.name == "nonce" })?.value else {
            return false
        }
        return constantTimeEquals(candidate, pairingNonce)
    }

    func hasConfirmation(_ queryItems: [URLQueryItem]) -> Bool {
        guard let candidate = queryItems.first(where: { $0.name == "code" || $0.name == "confirmation" })?.value else {
            return false
        }
        return constantTimeEquals(candidate, confirmationCode)
    }

    private func pairingDeepLink() -> String {
        var components = URLComponents()
        components.scheme = "swoosh"
        components.host = "pair"
        components.queryItems = [
            URLQueryItem(name: "host", value: daemonHost),
            URLQueryItem(name: "pairing", value: pairingNonce),
            URLQueryItem(name: "callback", value: callbackURL),
            URLQueryItem(name: "setup_url", value: setupURL),
            URLQueryItem(name: "code", value: confirmationCode),
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

    private static let css = """
    :root { color-scheme: dark; }
    body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #050505; color: #f4f4f3; font: 17px -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; }
    main { width: min(88vw, 360px); text-align: center; }
    h1 { margin: 0 0 12px; font-size: 32px; letter-spacing: 0; }
    p { margin: 0 0 22px; color: #c6c6c3; line-height: 1.38; }
    .button { display: block; margin: 12px 0; padding: 15px 18px; border-radius: 8px; background: #b5522d; color: white; text-decoration: none; font-weight: 700; }
    .secondary { background: #f1f1ef; color: #0a0a0a; }
    """
}

func htmlEscape(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

func urlQueryEscape(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
}

func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
    let left = Array(lhs.utf8)
    let right = Array(rhs.utf8)
    guard left.count == right.count else { return false }
    var diff: UInt8 = 0
    for index in 0..<left.count {
        diff |= left[index] ^ right[index]
    }
    return diff == 0
}
