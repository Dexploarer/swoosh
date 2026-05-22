// SwooshPluginRuntime/BundledPluginLoader.swift — 0.8B Bundled Plugin Discovery
//
// Walks `Plugins/<id>/manifest.json` and copies any manifest that isn't
// already in the store. Idempotent and *non-destructive* — if the user has
// toggled `enabled` on a previously-installed copy, the bundled copy never
// overwrites that state. This mirrors `BundledSkillLoader`'s contract.
//
// The loader does not enable plugins. The user must explicitly enable each
// one through the (humanOnly admin) `pluginEnable` call, even for the
// bundled HelloSwift demo.

import Foundation
import SwooshPlugins

public actor BundledPluginLoader {
    public let directory: URL
    private let store: any PluginStore
    private let decoder: JSONDecoder

    public init(store: any PluginStore, directory: URL) {
        self.store = store
        self.directory = directory.standardizedFileURL
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public static func defaultDirectory() -> URL {
        URL(fileURLWithPath: "Plugins", isDirectory: true,
            relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    }

    /// Result of one loader pass.
    public struct Outcome: Sendable {
        public let installed: [String]
        public let skipped: [String]
        public let failed: [String]
    }

    @discardableResult
    public func loadAll() async throws -> Outcome {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else {
            return Outcome(installed: [], skipped: [], failed: [])
        }
        let entries = (try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var installed: [String] = []
        var skipped: [String] = []
        var failed: [String] = []

        for entry in entries {
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }
            let manifestURL = entry.appendingPathComponent("manifest.json")
            guard fm.fileExists(atPath: manifestURL.path) else { continue }
            do {
                let data = try Data(contentsOf: manifestURL)
                let manifest = try decoder.decode(PluginManifest.self, from: data)
                if try await store.get(manifest.id) != nil {
                    skipped.append(manifest.id)
                    continue
                }
                // Bundled plugins land disabled. User must enable explicitly.
                var bundled = manifest
                bundled.enabled = false
                try await store.upsert(bundled)
                installed.append(manifest.id)
            } catch {
                failed.append(entry.lastPathComponent)
            }
        }
        return Outcome(installed: installed, skipped: skipped, failed: failed)
    }
}
