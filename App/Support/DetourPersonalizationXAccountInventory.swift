// DetourPersonalizationXAccountInventory.swift — personalization setup services (0.5A)

import Foundation

@MainActor
extension DetourPersonalizationRunner {
    func browserXAccounts(identityHints: Set<String>) -> [BrowserAccountFinding] {
        var findings: [BrowserAccountFinding] = []
        for profile in chromiumBrowserProfiles() {
            let cookieNames = xCookieNames(from: profile.cookiesURL)
            let hasSessionCookie = !cookieNames.isDisjoint(with: ["auth_token", "ct0", "twid"])
            let historyHandles = xHandlesFromHistory(profile.historyURL)
            let historyTextHandles = xHandlesFromHistoryText(profile.historyURL)
            let loginHandles = xHandlesFromLogins(profile.loginDataURL)
            let storageHandles = xHandlesFromWebStorage(profile)
            let inferredHandles = hasSessionCookie
                ? historyHandles.filter { identityHints.contains($0) || browserAccountScope($0) == .agent }
                : []
            let profileEvidenceHandles = hasSessionCookie
                ? historyTextHandles.filter { identityHints.contains($0) || browserAccountScope($0) == .agent }
                : []
            let handles = Set(inferredHandles).union(profileEvidenceHandles).union(loginHandles).union(storageHandles)
            for handle in handles {
                let evidence = hasSessionCookie && (inferredHandles.contains(handle) || profileEvidenceHandles.contains(handle))
                    ? "session cookies plus matching account metadata"
                    : "saved account metadata"
                findings.append(BrowserAccountFinding(
                    browser: profile.browser,
                    profile: profile.profile,
                    profileEmail: profile.profileEmail,
                    profileName: profile.profileName,
                    account: handle,
                    evidence: evidence,
                    scope: browserAccountScope(handle)
                ))
            }
            if hasSessionCookie, let email = profile.profileEmail {
                findings.append(BrowserAccountFinding(
                    browser: profile.browser,
                    profile: profile.profile,
                    profileEmail: profile.profileEmail,
                    profileName: profile.profileName,
                    account: email,
                    evidence: "session cookies in \(email) Chrome profile",
                    scope: browserProfileAccountScope(email)
                ))
            }
        }
        var seen = Set<String>()
        return findings
            .sorted { lhs, rhs in
                if lhs.scope.rawValue == rhs.scope.rawValue {
                    return lhs.account < rhs.account
                }
                return lhs.scope == .agent
            }
            .filter { seen.insert("\($0.browser):\($0.profile):\($0.account)").inserted }
    }

    func chromiumBrowserProfiles() -> [ChromiumBrowserProfile] {
        let home = fileManager.homeDirectoryForCurrentUser
        let roots: [(String, URL)] = [
            ("Chrome", home.appending(path: "Library/Application Support/Google/Chrome")),
            ("Arc", home.appending(path: "Library/Application Support/Arc/User Data")),
            ("Brave", home.appending(path: "Library/Application Support/BraveSoftware/Brave-Browser")),
            ("Edge", home.appending(path: "Library/Application Support/Microsoft Edge")),
            ("Chromium", home.appending(path: "Library/Application Support/Chromium")),
        ]
        var profiles: [ChromiumBrowserProfile] = []
        for (browser, root) in roots where directoryExists(root) {
            let profileMetadata = chromiumProfileMetadata(root: root)
            guard let children = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for child in children {
                guard (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                    continue
                }
                let history = child.appending(path: "History")
                let loginData = child.appending(path: "Login Data")
                let networkCookies = child.appending(path: "Network/Cookies")
                let legacyCookies = child.appending(path: "Cookies")
                let cookies = fileManager.fileExists(atPath: networkCookies.path) ? networkCookies : legacyCookies
                guard fileManager.fileExists(atPath: history.path)
                    || fileManager.fileExists(atPath: loginData.path)
                    || fileManager.fileExists(atPath: cookies.path) else {
                    continue
                }
                profiles.append(ChromiumBrowserProfile(
                    browser: browser,
                    profile: child.lastPathComponent,
                    profileEmail: profileMetadata[child.lastPathComponent]?.email,
                    profileName: profileMetadata[child.lastPathComponent]?.name,
                    profileRoot: child,
                    historyURL: history,
                    loginDataURL: loginData,
                    cookiesURL: cookies
                ))
            }
        }
        return profiles
    }

    func chromiumProfileMetadata(root: URL) -> [String: ChromiumProfileMetadata] {
        let localState = root.appending(path: "Local State")
        guard let data = try? Data(contentsOf: localState),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = object["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: [String: Any]] else {
            return [:]
        }
        return cache.mapValues { value in
            ChromiumProfileMetadata(
                email: (value["user_name"] as? String)?.nilIfEmpty,
                name: (value["gaia_name"] as? String)?.nilIfEmpty
                    ?? (value["given_name"] as? String)?.nilIfEmpty
                    ?? (value["name"] as? String)?.nilIfEmpty
            )
        }
    }

    func identityHints(userName: String, git: GitActivityInventory) -> Set<String> {
        let rawValues = [
            userName,
            git.gitUserName,
            git.gitUserEmail,
            NSUserName(),
            NSFullUserName(),
        ].compactMap(\.self)
        var hints = Set<String>()
        for raw in rawValues {
            let lowered = raw.lowercased()
            for token in lowered.components(separatedBy: CharacterSet.alphanumerics.inverted) where isXHandle(token) {
                hints.insert(token)
            }
            if let emailLocal = lowered.split(separator: "@").first.map(String.init), isXHandle(emailLocal) {
                hints.insert(emailLocal)
            }
        }
        return hints
    }

    func xCookieNames(from database: URL) -> Set<String> {
        let query = """
        SELECT DISTINCT name FROM cookies
        WHERE host_key = 'x.com'
           OR host_key = '.x.com'
           OR host_key LIKE '%.x.com'
           OR host_key = 'twitter.com'
           OR host_key = '.twitter.com'
           OR host_key LIKE '%.twitter.com';
        """
        return Set(sqliteRows(database: database, query: query))
    }

    func xHandlesFromHistory(_ database: URL) -> Set<String> {
        let query = """
        SELECT DISTINCT url FROM urls
        WHERE url LIKE 'https://x.com/%' OR url LIKE 'https://twitter.com/%'
        LIMIT 2000;
        """
        return Set(sqliteRows(database: database, query: query).compactMap(xHandle(fromURL:)))
    }

    func xHandlesFromHistoryText(_ database: URL) -> Set<String> {
        let query = """
        SELECT DISTINCT title FROM urls
        WHERE (url LIKE 'https://x.com/%' OR url LIKE 'https://twitter.com/%')
          AND title LIKE '%@%'
        LIMIT 2000;
        """
        var handles = Set<String>()
        for title in sqliteRows(database: database, query: query) {
            handles.formUnion(xHandles(fromText: title))
        }
        return handles
    }

    func xHandlesFromLogins(_ database: URL) -> Set<String> {
        let query = """
        SELECT DISTINCT username_value FROM logins
        WHERE origin_url LIKE 'https://x.com%'
           OR origin_url LIKE 'https://%.x.com%'
           OR origin_url LIKE 'https://twitter.com%'
           OR origin_url LIKE 'https://%.twitter.com%'
        LIMIT 200;
        """
        return Set(sqliteRows(database: database, query: query).compactMap(xHandle(fromLabel:)))
    }

    func xHandles(fromText text: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: #"@([A-Za-z_][A-Za-z0-9_]{2,14})"#) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return Set(regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let handleRange = Range(match.range(at: 1), in: text) else {
                return nil
            }
            let handle = String(text[handleRange]).lowercased()
            return isLikelyAccountHandleFromStorage(handle) ? handle : nil
        })
    }

    func xHandlesFromWebStorage(_ profile: ChromiumBrowserProfile) -> Set<String> {
        let directories = [
            profile.profileRoot.appending(path: "Local Storage/leveldb"),
            profile.profileRoot.appending(path: "Session Storage"),
            profile.profileRoot.appending(path: "IndexedDB/https_x.com_0.indexeddb.leveldb"),
            profile.profileRoot.appending(path: "IndexedDB/https_twitter.com_0.indexeddb.leveldb"),
        ]
        var handles = Set<String>()
        for directory in directories where directoryExists(directory) {
            guard let files = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for file in files where ["ldb", "log"].contains(file.pathExtension.lowercased()) {
                guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                      values.isRegularFile == true,
                      (values.fileSize ?? 0) <= 8_000_000,
                      let data = try? Data(contentsOf: file),
                      let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                    continue
                }
                handles.formUnion(xHandlesFromStorageText(text))
            }
        }
        return handles
    }

    func xHandlesFromStorageText(_ text: String) -> Set<String> {
        let patterns = [
            #""(?:screen_name|screenName|userName|username|handle|screenNameRaw)"\s*:\s*"?@?([A-Za-z_][A-Za-z0-9_]{2,14})"#,
            #"(?i)(?:screen_name|screenName|userName|username|handle)[^A-Za-z0-9_@]{1,24}@?([A-Za-z_][A-Za-z0-9_]{2,14})"#,
            #"https://(?:www\.)?(?:x|twitter)\.com/([A-Za-z_][A-Za-z0-9_]{2,14})(?:[/?#"\s]|$)"#,
        ]
        var handles = Set<String>()
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: range).prefix(200) {
                guard match.numberOfRanges > 1,
                      let handleRange = Range(match.range(at: 1), in: text) else {
                    continue
                }
                let handle = String(text[handleRange]).lowercased()
                let fullMatch = Range(match.range(at: 0), in: text).map { String(text[$0]).lowercased() } ?? ""
                if isLikelyAccountHandleFromStorage(handle),
                   storageContextMatchesX(text: text, range: match.range(at: 0), matchedText: fullMatch) {
                    handles.insert(handle)
                }
            }
        }
        return handles
    }

    func storageContextMatchesX(text: String, range: NSRange, matchedText: String) -> Bool {
        if matchedText.contains("x.com") || matchedText.contains("twitter.com") || matchedText.contains("screen_name") {
            return true
        }
        guard let swiftRange = Range(range, in: text) else { return false }
        let start = text.index(swiftRange.lowerBound, offsetBy: -512, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(swiftRange.upperBound, offsetBy: 512, limitedBy: text.endIndex) ?? text.endIndex
        let context = text[start..<end].lowercased()
        return context.contains("x.com") || context.contains("twitter.com")
    }

    func sqliteRows(database: URL, query: String) -> [String] {
        guard fileManager.fileExists(atPath: database.path),
              let sqlite = executable(named: "sqlite3") ?? (fileManager.isExecutableFile(atPath: "/usr/bin/sqlite3") ? URL(fileURLWithPath: "/usr/bin/sqlite3") : nil) else {
            return []
        }
        let temporary = fileManager.temporaryDirectory.appending(path: "detour-\(UUID().uuidString).sqlite")
        let target: URL
        if (try? fileManager.copyItem(at: database, to: temporary)) != nil {
            target = temporary
        } else {
            target = database
        }
        defer {
            if target == temporary {
                try? fileManager.removeItem(at: temporary)
            }
        }
        guard let output = runProcessOutput(
            executable: sqlite,
            arguments: ["-readonly", "-batch", "-noheader", target.path, query]
        ) else {
            return []
        }
        return output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func xHandle(fromURL urlString: String) -> String? {
        guard let components = URLComponents(string: urlString),
              let host = components.host?.lowercased(),
              host == "x.com" || host.hasSuffix(".x.com") || host == "twitter.com" || host.hasSuffix(".twitter.com") else {
            return nil
        }
        let parts = components.path
            .split(separator: "/")
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "@")) }
        guard let first = parts.first?.lowercased(),
              !xReservedPathComponents.contains(first),
              isXHandle(first) else {
            return nil
        }
        return first
    }

    func xHandle(fromLabel label: String) -> String? {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fromURL = xHandle(fromURL: trimmed) {
            return fromURL
        }
        let handle = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "@")).lowercased()
        guard isXHandle(handle), !xReservedPathComponents.contains(handle) else {
            return nil
        }
        return handle
    }

    var xReservedPathComponents: Set<String> {
        [
            "home", "explore", "notifications", "messages", "i", "intent",
            "search", "compose", "settings", "login", "logout", "signup",
            "share", "hashtag", "oauth", "account", "privacy", "tos",
            "download", "jobs", "status"
        ]
    }

    func isXHandle(_ value: String) -> Bool {
        guard (1...15).contains(value.count) else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
        }
    }

    func isLikelyAccountHandleFromStorage(_ value: String) -> Bool {
        guard isXHandle(value),
              !xReservedPathComponents.contains(value),
              value.count >= 3,
              value.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) || $0 == "_" }) else {
            return false
        }
        if value.unicodeScalars.allSatisfy({ CharacterSet.detourPersonalizationHexDigits.contains($0) }) {
            return false
        }
        return true
    }

    func browserAccountScope(_ handle: String) -> DetourDelegationRole {
        let value = handle.lowercased()
        if value.contains("detour")
            || value.contains("squirrel")
            || value.contains("agent") {
            return .agent
        }
        return .user
    }

    func browserProfileAccountScope(_ email: String) -> DetourDelegationRole {
        return .agent
    }
}
