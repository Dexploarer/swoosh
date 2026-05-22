// Tests/SwooshPluginsTests/ElizaAlignmentTests.swift — 0.8C
//
// Covers the elizaOS-style metadata fields added in 0.8C:
//   • PluginToolManifest.similes / examples / tags
//   • PluginManifest.dependencies / priority
//   • `actions` accepted as a decode alias for `tools`

import Testing
import Foundation
@testable import SwooshPlugins
@testable import SwooshTools

@Suite("elizaOS alignment — metadata fields")
struct ElizaAlignmentMetadataTests {

    @Test("PluginToolManifest defaults similes/examples/tags to empty")
    func toolDefaults() {
        let tool = PluginToolManifest(
            name: "x", description: "x",
            permission: .toolRead, risk: .readOnly, requiresApproval: false
        )
        #expect(tool.similes.isEmpty)
        #expect(tool.examples.isEmpty)
        #expect(tool.tags.isEmpty)
    }

    @Test("PluginToolManifest round-trips elizaOS-style fields")
    func toolRoundTrip() throws {
        let original = PluginToolManifest(
            name: "send", description: "send a message",
            permission: .networkAccess, risk: .medium, requiresApproval: true,
            similes: ["TRANSMIT", "DELIVER"],
            examples: ["send a message to alice"],
            tags: ["messaging", "social"]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PluginToolManifest.self, from: data)
        #expect(decoded.similes == ["TRANSMIT", "DELIVER"])
        #expect(decoded.examples == ["send a message to alice"])
        #expect(decoded.tags == ["messaging", "social"])
    }

    @Test("PluginManifest defaults dependencies and priority")
    func manifestDefaults() {
        let manifest = PluginManifest(
            id: "x", name: "x", version: "1.0",
            kind: .swift, entrypoint: .swiftModule("x"),
            requestedPermissions: ["toolRead"],
            tools: []
        )
        #expect(manifest.dependencies.isEmpty)
        #expect(manifest.priority == 0)
    }

    @Test("PluginManifest round-trips dependencies and priority")
    func manifestRoundTrip() throws {
        let original = PluginManifest(
            id: "x", name: "x", version: "1.0",
            kind: .swift, entrypoint: .swiftModule("x"),
            requestedPermissions: ["toolRead"],
            tools: [],
            dependencies: ["base", "logger"], priority: 5
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PluginManifest.self, from: data)
        #expect(decoded.dependencies == ["base", "logger"])
        #expect(decoded.priority == 5)
    }

    @Test("PluginManifest accepts `actions` as a decode alias for `tools`")
    func actionsAliasDecodes() throws {
        let json = #"""
        {
          "id": "x",
          "name": "x",
          "version": "1.0",
          "kind": "swift",
          "entrypoint": {"swiftModule": {"_0": "x"}},
          "requestedPermissions": ["toolRead"],
          "actions": [
            {"id":"1","name":"do_thing","description":"d","permission":"toolRead","risk":"readOnly","requiresApproval":false}
          ],
          "sandbox": {"allowFilesystemRead":false,"allowFilesystemWrite":false,"allowNetwork":false,"allowProcessSpawn":false,"allowedRoots":[],"maxOutputBytes":1024,"timeoutSeconds":5},
          "enabled": false,
          "createdAt": "2026-01-01T00:00:00Z",
          "updatedAt": "2026-01-01T00:00:00Z"
        }
        """#
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(PluginManifest.self, from: data)
        #expect(manifest.tools.count == 1)
        #expect(manifest.tools.first?.name == "do_thing")
    }

    @Test("Canonical encoding always emits `tools`, never `actions`")
    func canonicalEncodingUsesTools() throws {
        let manifest = PluginManifest(
            id: "x", name: "x", version: "1.0",
            kind: .swift, entrypoint: .swiftModule("x"),
            requestedPermissions: ["toolRead"],
            tools: [PluginToolManifest(name: "do_thing", description: "d", permission: .toolRead)]
        )
        let data = try JSONEncoder().encode(manifest)
        let text = String(data: data, encoding: .utf8) ?? ""
        #expect(text.contains("\"tools\""))
        #expect(!text.contains("\"actions\""))
    }
}
