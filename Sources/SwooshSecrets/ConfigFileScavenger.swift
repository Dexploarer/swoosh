// SwooshSecrets/ConfigFileScavenger.swift — Config file credential discovery
//
// Reads known credential/config files from disk.
// Mirrors CodexBar's auth-file resolution chain.

import Foundation

public enum ConfigFileScavenger {

    /// Known credential file locations.
    struct ConfigSource {
        let provider: KnownProvider
        let paths: [String]           // Relative to $HOME
        let extractor: (Data) -> String?
    }

    static var sources: [ConfigSource] {[
        // ── OpenAI / Codex CLI ──
        ConfigSource(provider: .openAI, paths: [
            ".codex/credentials.json",
            ".config/openai/credentials.json",
        ], extractor: { jsonKey($0, keys: ["api_key", "apiKey", "token"]) }),

        // ── Anthropic / Claude Code ──
        ConfigSource(provider: .anthropic, paths: [
            ".claude/credentials.json",
            ".config/claude/credentials.json",
            ".claude.json",
        ], extractor: { jsonKey($0, keys: ["apiKey", "api_key", "claudeApiKey"]) }),

        // ── OpenRouter ──
        ConfigSource(provider: .openRouter, paths: [
            ".config/openrouter/credentials.json",
        ], extractor: { jsonKey($0, keys: ["api_key", "apiKey", "token"]) }),

        // ── Gemini CLI ──
        ConfigSource(provider: .gemini, paths: [
            "Library/Application Support/gemini/credentials.json",
            ".config/gemini/credentials.json",
        ], extractor: { data in
            // Gemini CLI stores OAuth tokens
            jsonKey(data, keys: ["access_token", "api_key", "token"])
        }),

        // ── GitHub Copilot ──
        ConfigSource(provider: .copilot, paths: [
            ".config/github-copilot/hosts.json",
            ".config/github-copilot/apps.json",
        ], extractor: { data in
            // hosts.json has {"github.com": {"oauth_token": "gho_xxx"}}
            guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            for (_, hostVal) in dict {
                if let hostDict = hostVal as? [String: Any],
                   let token = hostDict["oauth_token"] as? String, !token.isEmpty {
                    return token
                }
            }
            return jsonKey(data, keys: ["oauth_token", "token"])
        }),

        // ── DeepSeek ──
        ConfigSource(provider: .deepSeek, paths: [
            ".config/deepseek/credentials.json",
        ], extractor: { jsonKey($0, keys: ["api_key", "apiKey"]) }),

        // ── Groq ──
        ConfigSource(provider: .groq, paths: [
            ".config/groq/credentials.json",
        ], extractor: { jsonKey($0, keys: ["api_key", "apiKey"]) }),

        // ── Mistral ──
        ConfigSource(provider: .mistral, paths: [
            ".config/mistral/credentials.json",
        ], extractor: { jsonKey($0, keys: ["api_key", "apiKey"]) }),

        // ── Perplexity ──
        ConfigSource(provider: .perplexity, paths: [
            ".config/perplexity/credentials.json",
        ], extractor: { jsonKey($0, keys: ["api_key", "apiKey", "session_token"]) }),
    ]}

    public static func scan() -> [DiscoveredCredential] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var results: [DiscoveredCredential] = []

        for source in sources {
            for relPath in source.paths {
                let url = home.appendingPathComponent(relPath)
                guard let data = try? Data(contentsOf: url) else { continue }
                guard let value = source.extractor(data), !value.isEmpty else { continue }

                results.append(DiscoveredCredential(
                    provider: source.provider,
                    source: .configFile,
                    kind: .apiKey,
                    value: value
                ))
                break // first file match for this provider wins
            }
        }

        return results
    }

    // ── JSON helpers ──

    /// Extract first matching key from a flat or nested JSON object.
    static func jsonKey(_ data: Data, keys: [String]) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return jsonKeyFromDict(obj, keys: keys)
    }

    private static func jsonKeyFromDict(_ dict: [String: Any], keys: [String]) -> String? {
        // Try top level first
        for key in keys {
            if let value = dict[key] as? String, !value.isEmpty {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        // Try one level of nesting
        for (_, nested) in dict {
            if let nestedDict = nested as? [String: Any] {
                for key in keys {
                    if let value = nestedDict[key] as? String, !value.isEmpty {
                        return value.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
        }
        return nil
    }
}
