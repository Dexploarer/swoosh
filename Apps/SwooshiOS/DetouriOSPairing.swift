// DetouriOSPairing.swift — URL pairing parser for the rebuilt iPhone app (0.5A)

import Foundation

struct DetouriOSPairingPayload: Equatable {
    let hostURL: URL
    let token: String
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

        guard let token = items.first(where: { $0.name == "token" })?.value,
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DetouriOSPairingError.missingToken
        }

        let minimumAppVersion = items.first(where: { $0.name == "min_ios_version" || $0.name == "required_ios_version" })?.value
        if let minimumAppVersion,
           !minimumAppVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !appVersionIsCurrentEnough(minimumAppVersion) {
            throw DetouriOSPairingError.appVersionTooOld(
                required: minimumAppVersion,
                current: currentAppVersion
            )
        }

        return DetouriOSPairingPayload(hostURL: hostURL, token: token, minimumAppVersion: minimumAppVersion)
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
    case missingToken
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
        case .missingToken:
            "The pairing link is missing the daemon token."
        case .appVersionTooOld(let required, let current):
            "Update Detour to \(required). This iPhone has \(current)."
        }
    }
}
