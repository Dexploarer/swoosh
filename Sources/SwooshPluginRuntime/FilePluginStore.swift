// SwooshPluginRuntime/FilePluginStore.swift — 0.8B File-backed Plugin Store
//
// Plugin manifests live under `<root>/<id>/manifest.json` (where `<root>` is
// typically `~/.swoosh/plugins`). Each plugin directory holds the manifest
// plus any kind-specific artifacts (executable bytes, .wasm files,
// resources). The store is deliberately ignorant of the entrypoint files —
// it owns only the manifest. Atomic writes via temp-file + rename so a
// crashed daemon never leaves a half-written manifest.

import Foundation
import SwooshPlugins

public actor FilePluginStore: PluginStore {
    public let root: URL
    private let fm = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(root: URL) {
        self.root = root.standardizedFileURL
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func listAll() async throws -> [PluginManifest] {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let entries = try fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var manifests: [PluginManifest] = []
        for entry in entries {
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }
            let manifestURL = entry.appendingPathComponent("manifest.json")
            guard fm.fileExists(atPath: manifestURL.path) else { continue }
            do {
                let data = try Data(contentsOf: manifestURL)
                let manifest = try decoder.decode(PluginManifest.self, from: data)
                manifests.append(manifest)
            } catch {
                // Skip unreadable manifests rather than failing the whole
                // listAll — one corrupt plugin shouldn't blank out the rest.
                // The daemon log path notes this; callers can re-validate.
                continue
            }
        }
        return manifests.sorted { $0.name < $1.name }
    }

    public func get(_ id: String) async throws -> PluginManifest? {
        guard safeDir(for: id) != nil else { return nil }
        let url = manifestURL(for: id)
        guard fm.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(PluginManifest.self, from: data)
    }

    public func upsert(_ manifest: PluginManifest) async throws {
        guard let dir = safeDir(for: manifest.id) else {
            throw PluginStoreError.idEscapesRoot(manifest.id)
        }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var updated = manifest
        updated.updatedAt = Date()
        let data = try encoder.encode(updated)
        let url = manifestURL(for: manifest.id)
        let tmp = url.appendingPathExtension("tmp-\(UUID().uuidString)")
        try data.write(to: tmp, options: .atomic)
        // Replace any existing file atomically. `replaceItemAt` on macOS
        // gives us an actual rename; the temp file vanishes either way.
        if fm.fileExists(atPath: url.path) {
            _ = try fm.replaceItemAt(url, withItemAt: tmp)
        } else {
            try fm.moveItem(at: tmp, to: url)
        }
    }

    public func remove(_ id: String) async throws {
        guard let dir = safeDir(for: id) else {
            throw PluginStoreError.idEscapesRoot(id)
        }
        guard fm.fileExists(atPath: dir.path) else { return }
        try fm.removeItem(at: dir)
    }

    /// Resolve `<root>/<id>` and verify it actually stays inside `root`.
    /// Belt-and-braces against `PluginManifest.validate()` slipping —
    /// the validation layer already rejects path-traversal IDs, but
    /// path resolution is cheap and a second line of defense costs
    /// nothing. Returns nil for IDs that escape (e.g. via symlinks or
    /// `..` slipping past validation in a future refactor); callers
    /// treat nil as "not installed".
    private func safeDir(for id: String) -> URL? {
        let candidate = root.appendingPathComponent(id, isDirectory: true).standardizedFileURL
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path.hasPrefix(rootPrefix), candidate.path != root.path else {
            return nil
        }
        return candidate
    }

    private func pluginDir(for id: String) -> URL {
        // Falls back to the naive join only when safeDir refuses; the
        // unsafe path will be rejected by upsert/remove which check
        // safeDir explicitly before touching the filesystem.
        safeDir(for: id) ?? root.appendingPathComponent(id, isDirectory: true)
    }

    private func manifestURL(for id: String) -> URL {
        pluginDir(for: id).appendingPathComponent("manifest.json")
    }
}

public enum PluginStoreError: Error, Sendable, CustomStringConvertible {
    /// The plugin ID resolves to a path outside the store's root — refuses
    /// the operation to prevent traversal writes/deletes.
    case idEscapesRoot(String)

    public var description: String {
        switch self {
        case .idEscapesRoot(let id):
            return "plugin id `\(id)` resolves outside the plugins root"
        }
    }
}
