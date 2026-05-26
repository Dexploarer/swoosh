// DetourXBrowserSessionExporter.swift — X browser-session credential bridge (0.5A)

import CommonCrypto
import Foundation
#if canImport(Security)
import Security
#endif

struct DetourXBrowserSessionExportResult {
    var importedKeys: Set<String>
    var profileCount: Int

    static let empty = DetourXBrowserSessionExportResult(importedKeys: [], profileCount: 0)
}

@MainActor
extension DetourPersonalizationRunner {
    func exportApprovedXBrowserSessionCredentials(
        candidates: [DetourSetupCandidate],
        approvedCandidateIDs: Set<String>,
        setupCandidateScopes: [String: DetourDelegationRole]
    ) -> DetourXBrowserSessionExportResult {
        guard approvedCandidateIDs.contains("connector.x")
            || approvedCandidateIDs.contains("credential.x")
            || approvedCandidateIDs.contains(where: { $0.hasPrefix("credential.x.") }) else {
            return .empty
        }
        let approvedX = candidates.filter { candidate in
            approvedCandidateIDs.contains(candidate.id)
                && (candidate.id == "credential.x" || candidate.id.hasPrefix("credential.x."))
        }
        let selectedIDs = Set(approvedX.map(\.id))
        var imported: Set<String> = []
        var profileCount = 0
        for profile in chromiumBrowserProfiles() where shouldExportXProfile(profile, selectedIDs: selectedIDs) {
            guard let cookies = xSessionCookies(from: profile),
                  let authToken = cookies["auth_token"],
                  let ct0 = cookies["ct0"] else {
                continue
            }
            let scope = scopeForXProfile(profile, candidates: approvedX, scopes: setupCandidateScopes)
            if storeXCookiePair(authToken: authToken, ct0: ct0, scope: scope) {
                imported.formUnion(["X_AUTH_TOKEN", "X_CT0"])
                profileCount += 1
            }
            if scope == .agent {
                break
            }
        }
        return DetourXBrowserSessionExportResult(importedKeys: imported, profileCount: profileCount)
    }

    private func shouldExportXProfile(_ profile: ChromiumBrowserProfile, selectedIDs: Set<String>) -> Bool {
        guard !selectedIDs.isEmpty, !selectedIDs.contains("credential.x") else { return true }
        let browser = stableIDComponent(profile.browser)
        let profileName = stableIDComponent(profile.profile)
        return selectedIDs.contains { id in
            id.hasSuffix(".\(browser).\(profileName)")
                || id.contains(".\(browser).\(profileName)")
        }
    }

    private func scopeForXProfile(
        _ profile: ChromiumBrowserProfile,
        candidates: [DetourSetupCandidate],
        scopes: [String: DetourDelegationRole]
    ) -> DetourDelegationRole {
        let browser = stableIDComponent(profile.browser)
        let profileName = stableIDComponent(profile.profile)
        let matches = candidates.filter { candidate in
            candidate.id == "credential.x"
                || candidate.id.hasSuffix(".\(browser).\(profileName)")
                || candidate.id.contains(".\(browser).\(profileName)")
        }
        if matches.contains(where: { (scopes[$0.id] ?? $0.scope) == .agent }) {
            return .agent
        }
        return matches.first.flatMap { scopes[$0.id] ?? $0.scope } ?? .user
    }

    private func xSessionCookies(from profile: ChromiumBrowserProfile) -> [String: String]? {
        guard let password = browserSafeStoragePassword(profile.browser) else { return nil }
        let query = """
        SELECT name || char(31) || host_key || char(31) || ifnull(value, '') || char(31) || hex(encrypted_value)
        FROM cookies
        WHERE name IN ('auth_token', 'ct0')
          AND (
            host_key = 'x.com'
            OR host_key = '.x.com'
            OR host_key LIKE '%.x.com'
            OR host_key = 'twitter.com'
            OR host_key = '.twitter.com'
            OR host_key LIKE '%.twitter.com'
          );
        """
        var output: [String: String] = [:]
        for row in sqliteRows(database: profile.cookiesURL, query: query) {
            let parts = row.components(separatedBy: String(UnicodeScalar(31)))
            guard parts.count == 4 else { continue }
            let name = parts[0]
            if !parts[2].isEmpty {
                output[name] = parts[2]
                continue
            }
            guard let encrypted = Data(hexString: parts[3]),
                  let value = decryptChromiumCookie(encrypted, host: parts[1], password: password) else {
                continue
            }
            output[name] = value
        }
        return output.isEmpty ? nil : output
    }

    private func browserSafeStoragePassword(_ browser: String) -> String? {
        let labels: [String: (service: String, account: String)] = [
            "Chrome": ("Chrome Safe Storage", "Chrome"),
            "Brave": ("Brave Safe Storage", "Brave"),
            "Edge": ("Microsoft Edge Safe Storage", "Microsoft Edge"),
            "Arc": ("Arc Safe Storage", "Arc"),
            "Chromium": ("Chromium Safe Storage", "Chromium"),
        ]
        guard let label = labels[browser] else { return nil }
        return readGenericPassword(service: label.service, account: label.account)
    }

    private func decryptChromiumCookie(_ encrypted: Data, host: String, password: String) -> String? {
        guard encrypted.count > 3 else { return nil }
        let payload = encrypted.starts(with: Data("v10".utf8)) || encrypted.starts(with: Data("v11".utf8))
            ? encrypted.dropFirst(3)
            : encrypted[encrypted.startIndex...]
        guard let key = chromiumCookieKey(password: password) else { return nil }
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        let outputCapacity = payload.count + kCCBlockSizeAES128
        var output = Data(count: payload.count + kCCBlockSizeAES128)
        var outputLength = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            payload.withUnsafeBytes { payloadBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            payloadBytes.baseAddress,
                            payload.count,
                            outputBytes.baseAddress,
                            outputCapacity,
                            &outputLength
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        output.removeSubrange(outputLength..<output.count)
        if let value = String(data: output, encoding: .utf8) {
            return value
        }
        guard output.count > 32 else { return nil }
        return String(data: output.dropFirst(32), encoding: .utf8)
    }

    private func chromiumCookieKey(password: String) -> Data? {
        let derivedLength = kCCKeySizeAES128
        var derived = Data(count: derivedLength)
        let salt = Data("saltysalt".utf8)
        let status = derived.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                password.withCString { passwordPointer in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordPointer,
                        strlen(passwordPointer),
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        1003,
                        derivedBytes.bindMemory(to: UInt8.self).baseAddress,
                        derivedLength
                    )
                }
            }
        }
        return status == kCCSuccess ? derived : nil
    }

    private func storeXCookiePair(authToken: String, ct0: String, scope: DetourDelegationRole) -> Bool {
        let scopedPrefix = scope == .agent ? "agent" : "user"
        return [
            ("x.auth_token", authToken),
            ("x.ct0", ct0),
            ("x.\(scopedPrefix)_auth_token", authToken),
            ("x.\(scopedPrefix)_ct0", ct0),
            ("legacy.X_AUTH_TOKEN", authToken),
            ("legacy.X_CT0", ct0),
        ].allSatisfy { account, value in
            setGenericPassword(value, service: "ai.swoosh.secrets", account: account)
        }
    }
}

private func readGenericPassword(service: String, account: String) -> String? {
    #if canImport(Security)
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: AnyObject?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
          let data = result as? Data else {
        return nil
    }
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    #else
    return nil
    #endif
}

private func setGenericPassword(_ value: String, service: String, account: String) -> Bool {
    #if canImport(Security)
    guard let data = value.data(using: .utf8) else { return false }
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
    ]
    var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecItemNotFound {
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        status = SecItemAdd(add as CFDictionary, nil)
    }
    return status == errSecSuccess
    #else
    return false
    #endif
}

private extension Data {
    init?(hexString: String) {
        guard hexString.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self = Data(bytes)
    }
}
