// Tests/SwooshPluginRuntimeTests/BundledHelloSwiftTests.swift — 0.8B
//
// Validates the hand-written `Plugins/HelloSwift/manifest.json` actually
// decodes against `PluginManifest`. Every other test in this suite goes
// through Swift's synthesized `Codable` round-trip; this is the one place
// the on-disk JSON shape (notably the enum-with-associated-value
// `entrypoint`) gets exercised. If the JSON drifts from what
// `BundledPluginLoader` expects, the daemon silently logs "failed to read
// bundled HelloSwift" and the demo vanishes — that bug is caught here.

import Testing
import Foundation
@testable import SwooshPlugins
@testable import SwooshPluginRuntime
@testable import SwooshTools

@Suite("Bundled HelloSwift manifest")
struct BundledHelloSwiftTests {

    /// The bundled manifest lives at the repo root; tests run with that as
    /// the working directory under `swift test`.
    private var manifestURL: URL {
        URL(fileURLWithPath: "Plugins/HelloSwift/manifest.json")
    }

    @Test("manifest decodes")
    func decodes() throws {
        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(PluginManifest.self, from: data)
        #expect(manifest.id == "hello-swift")
        #expect(manifest.kind == .swift)
        #expect(manifest.tools.count == 1)
        #expect(manifest.tools.first?.permission == .toolRead)
    }

    @Test("manifest validates")
    func validates() throws {
        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(PluginManifest.self, from: data)
        let errors = manifest.validate()
        #expect(errors.isEmpty, "validation errors: \(errors)")
    }

    @Test("manifest entrypoint is swiftModule(\"hello-swift\")")
    func entrypointShape() throws {
        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(PluginManifest.self, from: data)
        if case .swiftModule(let name) = manifest.entrypoint {
            #expect(name == "hello-swift")
        } else {
            Issue.record("entrypoint shape mismatch: \(manifest.entrypoint)")
        }
    }

    @Test("BundledPluginLoader installs the bundled manifest")
    func loaderInstalls() async throws {
        // Use a temp store so we don't touch ~/.swoosh.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("swoosh-bundled-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = FilePluginStore(root: tmp)
        let loader = BundledPluginLoader(
            store: store,
            directory: URL(fileURLWithPath: "Plugins")
        )
        let outcome = try await loader.loadAll()
        #expect(outcome.installed.contains("hello-swift"))
        #expect(outcome.failed.isEmpty, "loader reported failed: \(outcome.failed)")
        let read = try await store.get("hello-swift")
        #expect(read?.enabled == false, "bundled plugins must land disabled")
    }
}
