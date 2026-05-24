// Tests/SwooshSecretsTests/ConfigFileScavengerTests.swift
//
// Pins the JSON extractor used by `ConfigFileScavenger` to read
// `~/.codex/credentials.json` and friends. Doesn't touch the real
// filesystem — exercises the pure `jsonKey(_:keys:)` helper directly.

import Testing
import Foundation
@testable import SwooshSecrets

@Suite("ConfigFileScavenger.jsonKey")
struct ConfigFileScavengerJSONTests {

    @Test("Top-level key")
    func topLevelKey() throws {
        let data = try #require(#"{"api_key":"sk-top"}"#.data(using: .utf8))
        #expect(ConfigFileScavenger.jsonKey(data, keys: ["api_key"]) == "sk-top")
    }

    @Test("Picks first match in priority order")
    func priorityOrder() throws {
        let data = try #require(#"{"token":"tok-z","api_key":"sk-a"}"#.data(using: .utf8))
        // `api_key` listed first, both present — should return the first key in `keys`.
        #expect(ConfigFileScavenger.jsonKey(data, keys: ["api_key", "token"]) == "sk-a")
    }

    @Test("Falls through to nested object")
    func nestedKey() throws {
        let data = try #require(#"{"openai":{"apiKey":"sk-nested"}}"#.data(using: .utf8))
        #expect(ConfigFileScavenger.jsonKey(data, keys: ["apiKey"]) == "sk-nested")
    }

    @Test("Trims surrounding whitespace")
    func trimsWhitespace() throws {
        let data = try #require(#"{"api_key":"  sk-padded \n"}"#.data(using: .utf8))
        #expect(ConfigFileScavenger.jsonKey(data, keys: ["api_key"]) == "sk-padded")
    }

    @Test("Empty value treated as missing")
    func emptyValue() throws {
        let data = try #require(#"{"api_key":""}"#.data(using: .utf8))
        #expect(ConfigFileScavenger.jsonKey(data, keys: ["api_key"]) == nil)
    }

    @Test("Malformed JSON returns nil")
    func malformedJSON() {
        let data = Data("not json".utf8)
        #expect(ConfigFileScavenger.jsonKey(data, keys: ["api_key"]) == nil)
    }

    @Test("Unknown keys return nil")
    func unknownKeys() throws {
        let data = try #require(#"{"some_other_field":"x"}"#.data(using: .utf8))
        #expect(ConfigFileScavenger.jsonKey(data, keys: ["api_key", "token"]) == nil)
    }
}
