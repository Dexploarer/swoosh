// SwooshSecrets/EnvironmentScavenger.swift — 0.9S Env var credential discovery
//
// Checks standard environment variables for API keys.
// Mirrors CodexBar's ProviderTokenResolver.resolveEnv pattern.

import Foundation

public enum EnvironmentScavenger {

    /// Known env var → provider mappings.
    /// Order within each provider array is priority (first match wins).
    static let envMap: [(KnownProvider, [String])] = [
        (.openAI,     ["OPENAI_API_KEY", "OPENAI_KEY"]),
        (.openRouter, ["OPENROUTER_API_KEY", "OPENROUTER_KEY"]),
        (.elizaCloud, ["ELIZA_CLOUD_API_KEY", "ELIZACLOUD_API_KEY"]),
        (.anthropic,  ["ANTHROPIC_API_KEY", "CLAUDE_API_KEY"]),
        (.gemini,     ["GEMINI_API_KEY", "GOOGLE_API_KEY", "GOOGLE_GENERATIVE_AI_API_KEY"]),
        (.codex,      ["CODEX_AUTH_TOKEN", "OPENAI_CODEX_TOKEN"]),
    ]

    public static func scan(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [DiscoveredCredential] {
        var results: [DiscoveredCredential] = []

        for (provider, keys) in envMap {
            for key in keys {
                if let value = cleaned(environment[key]) {
                    results.append(DiscoveredCredential(
                        provider: provider,
                        source: .environment,
                        kind: .apiKey,
                        value: value
                    ))
                    break // first match for this provider wins
                }
            }
        }

        return results
    }

    /// Strip quotes and whitespace (same as CodexBar's cleaned()).
    private static func cleaned(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }

        // Strip surrounding quotes
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
           (value.hasPrefix("'") && value.hasSuffix("'")) {
            value.removeFirst()
            value.removeLast()
        }

        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
