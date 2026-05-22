// Tests/SwooshPluginRuntimeTests/FilePluginStoreTests.swift — 0.8B

import Testing
import Foundation
@testable import SwooshPlugins
@testable import SwooshPluginRuntime
@testable import SwooshTools

private func tempRoot() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("swoosh-plugin-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func sampleManifest(id: String = "demo", enabled: Bool = false) -> PluginManifest {
    PluginManifest(
        id: id, name: "Demo", version: "1.0.0",
        kind: .swift, entrypoint: .swiftModule(id),
        requestedPermissions: ["toolRead"],
        tools: [PluginToolManifest(
            name: "echo", description: "Echo",
            permission: .toolRead, risk: .readOnly, requiresApproval: false
        )],
        enabled: enabled
    )
}

@Suite("FilePluginStore")
struct FilePluginStoreTests {

    @Test("upsert + get round-trips a manifest")
    func roundTrip() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FilePluginStore(root: root)
        try await store.upsert(sampleManifest())
        let read = try await store.get("demo")
        #expect(read?.id == "demo")
        #expect(read?.tools.first?.permission == .toolRead)
    }

    @Test("listAll skips dirs without manifest.json")
    func listAllSkipsEmptyDirs() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("empty"), withIntermediateDirectories: true
        )
        let store = FilePluginStore(root: root)
        try await store.upsert(sampleManifest())
        let all = try await store.listAll()
        #expect(all.map(\.id) == ["demo"])
    }

    @Test("listAll skips corrupt manifests")
    func listAllSkipsCorrupt() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FilePluginStore(root: root)
        try await store.upsert(sampleManifest())
        // Drop a corrupt manifest next door
        let badDir = root.appendingPathComponent("broken", isDirectory: true)
        try FileManager.default.createDirectory(at: badDir, withIntermediateDirectories: true)
        try "not json".write(
            to: badDir.appendingPathComponent("manifest.json"),
            atomically: true, encoding: .utf8
        )
        let all = try await store.listAll()
        #expect(all.map(\.id) == ["demo"])
    }

    @Test("remove deletes the plugin dir")
    func removeWipes() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FilePluginStore(root: root)
        try await store.upsert(sampleManifest())
        try await store.remove("demo")
        let read = try await store.get("demo")
        #expect(read == nil)
    }

    @Test("upsert overwrites existing manifest atomically")
    func upsertReplaces() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FilePluginStore(root: root)
        try await store.upsert(sampleManifest(enabled: false))
        try await store.upsert(sampleManifest(enabled: true))
        let read = try await store.get("demo")
        #expect(read?.enabled == true)
    }
}
