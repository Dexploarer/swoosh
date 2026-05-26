// DetouriOSPairing.swift — URL pairing parser for the rebuilt iPhone app (0.5A)

import Foundation

struct DetouriOSPairingPayload: Equatable {
    let hostURL: URL
    let token: String?
    let pairingNonce: String?
    let confirmationCode: String?
    let callbackURL: URL?
    let setupURL: URL?
    let setupBundle: DetourSetupTransferBundle?
    let minimumAppVersion: String?
}

enum DetouriOSPairingSupport {
    static func parse(_ url: URL) throws -> DetouriOSPairingPayload {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw DetouriOSPairingError.invalidURL
        }

        guard components.scheme == "swoosh" || components.scheme == "detour" else {
            throw DetouriOSPairingError.unsupportedScheme
        }

        guard components.host == "pair" || components.path == "/pair" else {
            throw DetouriOSPairingError.unsupportedAction
        }

        let items = components.queryItems ?? []
        guard let rawHost = items.first(where: { $0.name == "host" })?.value,
              let hostURL = URL(string: rawHost),
              hostURL.scheme != nil,
              hostURL.host != nil else {
            throw DetouriOSPairingError.missingHost
        }

        let token = items.first(where: { $0.name == "token" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let pairingNonce = items.first(where: { $0.name == "pairing" || $0.name == "nonce" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        guard token != nil || pairingNonce != nil else {
            throw DetouriOSPairingError.missingPairingAuthorization
        }
        let callbackURL = items.first(where: { $0.name == "callback" || $0.name == "callback_url" })?.value
            .flatMap(URL.init(string:))
        let setupURL = items.first(where: { $0.name == "setup_url" })?.value
            .flatMap(URL.init(string:))
        let setupBundle = items.first(where: { $0.name == "setup" })?.value
            .flatMap { try? DetourSetupTransferBundle.decodeURLPayload($0) }
        let minimumAppVersion = items.first(where: { $0.name == "min_ios_version" || $0.name == "required_ios_version" })?.value
        if let minimumAppVersion,
           !minimumAppVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !appVersionIsCurrentEnough(minimumAppVersion) {
            throw DetouriOSPairingError.appVersionTooOld(
                required: minimumAppVersion,
                current: currentAppVersion
            )
        }

        return DetouriOSPairingPayload(
            hostURL: hostURL,
            token: token,
            pairingNonce: pairingNonce,
            confirmationCode: items.first(where: { $0.name == "code" || $0.name == "confirmation" })?.value,
            callbackURL: callbackURL,
            setupURL: setupURL,
            setupBundle: setupBundle,
            minimumAppVersion: minimumAppVersion
        )
    }

    private static var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    private static func appVersionIsCurrentEnough(_ required: String) -> Bool {
        compareVersions(currentAppVersion, required) != .orderedAscending
    }

    private static func compareVersions(_ left: String, _ right: String) -> ComparisonResult {
        let leftParts = versionParts(left)
        let rightParts = versionParts(right)
        let count = max(leftParts.count, rightParts.count)
        for index in 0..<count {
            let leftValue = index < leftParts.count ? leftParts[index] : 0
            let rightValue = index < rightParts.count ? rightParts[index] : 0
            if leftValue < rightValue { return .orderedAscending }
            if leftValue > rightValue { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func versionParts(_ version: String) -> [Int] {
        version
            .split { !$0.isNumber }
            .map { Int($0) ?? 0 }
    }
}

enum DetouriOSPairingError: LocalizedError {
    case invalidURL
    case unsupportedScheme
    case unsupportedAction
    case missingHost
    case missingPairingAuthorization
    case appVersionTooOld(required: String, current: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "That pairing link is not a valid URL."
        case .unsupportedScheme:
            "That link is not a Detour pairing link."
        case .unsupportedAction:
            "That Detour link is not a pairing action."
        case .missingHost:
            "The pairing link is missing the Mac daemon address."
        case .missingPairingAuthorization:
            "The pairing link is missing its pairing authorization."
        case .appVersionTooOld(let required, let current):
            "Update Detour to \(required). This iPhone has \(current)."
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
