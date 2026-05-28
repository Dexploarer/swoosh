// SwooshSecrets/ConfigFileScavenger.swift — 0.9S Config file credential discovery
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
        // ── OpenAI ──
        ConfigSource(provider: .openAI, paths: [
            ".codex/auth.json",
            ".codex/credentials.json",
            ".config/openai/credentials.json",
        ], extractor: { jsonKey($0, keys: ["access_token", "api_key", "apiKey", "token"]) }),

        // ── OpenRouter ──
        ConfigSource(provider: .openRouter, paths: [
            ".config/openrouter/credentials.json",
        ], extractor: { jsonKey($0, keys: ["api_key", "apiKey", "token"]) }),

        // ── Detour Cloud ──
        ConfigSource(provider: .detourCloud, paths: [
            ".config/detour-cloud/credentials.json",
            ".config/eliza/credentials.json",
        ], extractor: { jsonKey($0, keys: ["api_key", "apiKey", "token"]) }),
    ]}

    public static func scan() -> [DiscoveredCredential] {
        let home = swooshHomeDirectoryForCurrentUser()
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
