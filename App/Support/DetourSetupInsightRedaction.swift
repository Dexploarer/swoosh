// DetourSetupInsightRedaction.swift — display redaction for setup insights (0.5A)

import Foundation

enum DetourSetupInsightRedaction {
    static func display(_ value: String) -> String {
        let trimmed = collapsed(value)
        guard !trimmed.isEmpty else { return "" }
        if wholeValueIsSecret(trimmed) {
            return "Saved credential"
        }
        var output = trimmed
        for rule in replacementRules {
            output = output.replacingOccurrences(
                of: rule.pattern,
                with: rule.replacement,
                options: .regularExpression
            )
        }
        output = collapsed(output)
        guard !output.isEmpty else { return "" }
        return wholeValueIsSecret(output) ? "Saved credential" : output
    }

    static func displayOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let display = identifierDisplay(value)
        return display.isEmpty ? nil : display
    }

    static func displayList(_ values: [String]) -> [String] {
        values.compactMap(displayOptional)
    }

    static func stableID(prefix: String, components: [String]) -> String {
        ([prefix] + components)
            .map(stableIDComponent)
            .filter { !$0.isEmpty }
            .joined(separator: ".")
    }

    static func stableIDComponent(_ value: String) -> String {
        let display = identifierDisplay(value)
        let base = display.isEmpty ? "unknown" : display
        let slug = collapsed(
            base.lowercased().unicodeScalars.map { scalar in
                CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : "-"
            }.joined()
        )
            .replacingOccurrences(of: " ", with: "-")
            .split(separator: "-")
            .joined(separator: "-")
        let safeSlug = slug.isEmpty ? "unknown" : String(slug.prefix(72))
        return safeSlug
    }

    static func owner(from role: DetourDelegationRole?, category: DetourSetupCategory) -> DetourSetupInsightOwner {
        switch role {
        case .user:
            return .user
        case .agent:
            return .agent
        case nil:
            switch category {
            case .connector, .mcp, .skill, .model:
                return .agent
            case .context, .permission, .goal, .schedule:
                return .shared
            case .account, .identity:
                return .user
            }
        }
    }

    static func ownerLabel(_ owner: DetourSetupInsightOwner, userName: String, agentName: String) -> String {
        switch owner {
        case .user:
            let name = userName.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "User" : name
        case .agent:
            let name = agentName.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "Detour" : name
        case .shared:
            return "Shared"
        case .unknown:
            return "Choose owner"
        }
    }

    private static let redactedLabels: Set<String> = [
        "message contact",
        "phone number",
        "saved credential",
    ]

    private static let replacementRules: [(pattern: String, replacement: String)] = [
        ("(?is)-----BEGIN [^-]+PRIVATE KEY-----.*?-----END [^-]+PRIVATE KEY-----", "saved credential"),
        ("(?i)\\b(?:bearer|basic)\\s+[A-Za-z0-9._~+/=-]{12,}", "saved credential"),
        ("(?i)\\b(?:api[_ -]?key|token|secret|password|passwd|authorization|cookie|session)[A-Za-z0-9_ -]{0,32}\\s*[:=]\\s*[^\\s,;]+", "saved credential"),
        ("\\b(sk-[A-Za-z0-9_-]{8,}|xox[baprs]-[A-Za-z0-9-]{8,}|gh[pousr]_[A-Za-z0-9_]{8,}|github_pat_[A-Za-z0-9_]{8,}|hf_[A-Za-z0-9_]{8,}|AIza[0-9A-Za-z_-]{8,})\\b", "saved credential"),
        ("\\beyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\b", "saved credential"),
        ("\\b[A-Z][A-Z0-9_]*(?:TOKEN|SECRET|PASSWORD|PASS|KEY|COOKIE|SESSION|PAT)[A-Z0-9_]*\\b", "saved credential"),
        ("\\b[A-Fa-f0-9]{32,}\\b", "saved credential"),
        ("\\b[A-Za-z0-9_+/=-]{44,}\\b", "saved credential"),
        ("(?i)\\bmetadata matched\\b", "found"),
        ("(?i)\\bcookie store metadata\\b", "browser session"),
        ("(?i)\\bcookies?\\b", "browser session"),
        ("(?i)\\bbrowser history\\b", "browser activity summary"),
        ("(?i)\\blogin data\\b", "saved browser sign-in"),
        ("(?i)\\braw scout records?\\b", "local setup summary"),
        ("(?i)\\bscout records?\\b", "setup summary"),
        ("(?i)\\braw credentials?\\b", "saved access"),
        ("(?i)\\bcredential keys?\\b", "saved access names"),
        ("(?i)\\bcredential names?\\b", "saved access names"),
        ("(?i)\\benvironmentSecretRefs?\\b", "saved access references"),
        ("(?i)\\bsecret refs?\\b", "saved access references"),
        ("(?i)\\bmessage handles?\\b", "message contacts"),
        ("\\+?\\d[\\d .()\\-]{6,}\\d", "phone number"),
    ]

    private static func wholeValueIsSecret(_ value: String) -> Bool {
        let patterns = [
            "(?is)^-----BEGIN [^-]+PRIVATE KEY-----.*-----END [^-]+PRIVATE KEY-----$",
            "(?i)^(?:bearer|basic)\\s+[A-Za-z0-9._~+/=-]{12,}$",
            "^(sk-[A-Za-z0-9_-]{8,}|xox[baprs]-[A-Za-z0-9-]{8,}|gh[pousr]_[A-Za-z0-9_]{8,}|github_pat_[A-Za-z0-9_]{8,}|hf_[A-Za-z0-9_]{8,}|AIza[0-9A-Za-z_-]{8,})$",
            "^eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+$",
            "^[A-Z][A-Z0-9_]*(?:TOKEN|SECRET|PASSWORD|PASS|KEY|COOKIE|SESSION|PAT)[A-Z0-9_]*$",
            "^[A-Fa-f0-9]{32,}$",
            "^[A-Za-z0-9_+/=-]{44,}$",
        ]
        return patterns.contains { value.range(of: $0, options: .regularExpression) != nil }
    }

    private static func identifierDisplay(_ value: String) -> String {
        let displayed = display(value)
        return displayed
            .replacingOccurrences(
                of: "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}",
                with: "email",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: "@[A-Za-z_][A-Za-z0-9_]{2,30}",
                with: "handle",
                options: .regularExpression
            )
            .replacingOccurrences(of: "\\+?\\d[\\d .()\\-]{6,}\\d", with: "phone", options: .regularExpression)
    }

    private static func collapsed(_ value: String) -> String {
        value
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

}
