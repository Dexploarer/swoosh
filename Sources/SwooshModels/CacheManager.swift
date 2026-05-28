// SwooshModels/CacheManager.swift — Model cache discovery and cleanup — 0.9T
//
// Scans the four local model directories (Ollama, HuggingFace hub, MLX cache,
// Swoosh models), reports per-source and per-model disk usage, and supports
// selective or total purges. All types are Sendable so the SwiftUI layer can
// drive the scan from a `.task` block and bind directly.

import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - Cache source
// ═══════════════════════════════════════════════════════════════════

/// Which runtime's cache directory an entry belongs to.
public enum CacheSource: String, Codable, Sendable, CaseIterable, Identifiable {
    case ollama      = "ollama"
    case huggingface = "huggingface"
    case mlx         = "mlx"
    case swoosh      = "swoosh"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ollama:      return "Ollama"
        case .huggingface: return "HuggingFace"
        case .mlx:         return "MLX"
        case .swoosh:      return "Swoosh"
        }
    }

    /// Short pill label for the UI.
    public var badge: String {
        switch self {
        case .ollama:      return "Ollama"
        case .huggingface: return "HF"
        case .mlx:         return "MLX"
        case .swoosh:      return "Swoosh"
        }
    }

    var baseURL: URL {
        #if os(macOS)
        let home = FileManager.default.homeDirectoryForCurrentUser
        #else
        let home = URL(fileURLWithPath: NSHomeDirectory())
        #endif
        switch self {
        case .ollama:      return home.appending(path: ".ollama/models")
        case .huggingface: return home.appending(path: ".cache/huggingface/hub")
        case .mlx:         return home.appending(path: ".cache/mlx")
        case .swoosh:      return home.appending(path: ".swoosh/models")
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Cache entry
// ═══════════════════════════════════════════════════════════════════

/// A single cached model (or blob directory) on disk.
public struct CacheEntry: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let sizeBytes: UInt64
    public let source: CacheSource
    public let lastAccessed: Date
    public let path: URL

    /// Size formatted in GB (two decimal places).
    public var sizeGB: Double {
        Double(sizeBytes) / (1024 * 1024 * 1024)
    }

    public init(
        id: String,
        name: String,
        sizeBytes: UInt64,
        source: CacheSource,
        lastAccessed: Date,
        path: URL
    ) {
        self.id = id
        self.name = name
        self.sizeBytes = sizeBytes
        self.source = source
        self.lastAccessed = lastAccessed
        self.path = path
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Disk info
// ═══════════════════════════════════════════════════════════════════

/// Snapshot of the boot volume's disk usage.
public struct DiskInfo: Codable, Sendable {
    public let totalBytes: UInt64
    public let freeBytes: UInt64

    public var totalGB: Double { Double(totalBytes) / (1024 * 1024 * 1024) }
    public var freeGB: Double  { Double(freeBytes) / (1024 * 1024 * 1024) }
    public var usedGB: Double  { totalGB - freeGB }

    public init(totalBytes: UInt64, freeBytes: UInt64) {
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Cache snapshot
// ═══════════════════════════════════════════════════════════════════

/// Immutable result of a full cache scan.
public struct CacheSnapshot: Sendable {
    public let entries: [CacheEntry]
    public let disk: DiskInfo
    public let scannedAt: Date

    /// Total cached model bytes across all sources.
    public var totalCacheBytes: UInt64 {
        entries.reduce(0) { $0 + $1.sizeBytes }
    }

    public var totalCacheGB: Double {
        Double(totalCacheBytes) / (1024 * 1024 * 1024)
    }

    /// Bytes per source.
    public func bytes(for source: CacheSource) -> UInt64 {
        entries.filter { $0.source == source }.reduce(0) { $0 + $1.sizeBytes }
    }

    public func sizeGB(for source: CacheSource) -> Double {
        Double(bytes(for: source)) / (1024 * 1024 * 1024)
    }

    /// Entries belonging to a given source.
    public func entries(for source: CacheSource) -> [CacheEntry] {
        entries.filter { $0.source == source }
    }

    public init(entries: [CacheEntry], disk: DiskInfo, scannedAt: Date = .now) {
        self.entries = entries
        self.disk = disk
        self.scannedAt = scannedAt
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - CacheManager actor
// ═══════════════════════════════════════════════════════════════════

/// Discovers and manages cached model files across Ollama, HuggingFace,
/// MLX, and Swoosh directories.
public actor CacheManager {

    private let fm = FileManager.default

    public init() {}

    // MARK: - Scan

    /// Full scan — discovers every cached model entry and reads disk stats.
    public func scan() throws -> CacheSnapshot {
        var all: [CacheEntry] = []
        for source in CacheSource.allCases {
            all.append(contentsOf: scanSource(source))
        }
        all.sort { $0.sizeBytes > $1.sizeBytes }  // largest first
        let disk = try readDiskInfo()
        return CacheSnapshot(entries: all, disk: disk)
    }

    // MARK: - Purge

    /// Delete all cached models. Returns GB freed.
    @discardableResult
    public func purgeAll() throws -> Double {
        let snapshot = try scan()
        return try purge(entries: snapshot.entries)
    }

    /// Delete specific entries. Returns GB freed.
    @discardableResult
    public func purge(entries: [CacheEntry]) throws -> Double {
        var freed: UInt64 = 0
        for entry in entries {
            guard fm.fileExists(atPath: entry.path.path(percentEncoded: false)) else { continue }
            let size = entry.sizeBytes
            try fm.removeItem(at: entry.path)
            freed += size
        }
        return Double(freed) / (1024 * 1024 * 1024)
    }

    /// Delete all entries from a single source. Returns GB freed.
    @discardableResult
    public func purgeSource(_ source: CacheSource) throws -> Double {
        let snapshot = try scan()
        return try purge(entries: snapshot.entries(for: source))
    }

    // MARK: - Disk info

    private func readDiskInfo() throws -> DiskInfo {
        #if os(macOS)
        let home = fm.homeDirectoryForCurrentUser
        #else
        let home = URL(fileURLWithPath: NSHomeDirectory())
        #endif
        let attrs = try fm.attributesOfFileSystem(forPath: home.path(percentEncoded: false))
        let total = (attrs[.systemSize] as? NSNumber)?.uint64Value ?? 0
        let free  = (attrs[.systemFreeSize] as? NSNumber)?.uint64Value ?? 0
        return DiskInfo(totalBytes: total, freeBytes: free)
    }

    // MARK: - Per-source scanning

    private func scanSource(_ source: CacheSource) -> [CacheEntry] {
        let base = source.baseURL
        guard fm.fileExists(atPath: base.path(percentEncoded: false)) else { return [] }

        switch source {
        case .ollama:      return scanOllama(base)
        case .huggingface: return scanHuggingFace(base)
        case .mlx:         return scanMLX(base)
        case .swoosh:      return scanSwoosh(base)
        }
    }

    /// Ollama stores models as blob dirs under `~/.ollama/models/`.
    /// Walk top-level children (manifests/, blobs/) but attribute each
    /// to the "ollama" source as a single aggregate when structure is flat,
    /// or per-subdirectory when nested.
    private func scanOllama(_ base: URL) -> [CacheEntry] {
        var results: [CacheEntry] = []

        // blobs/ contains the heavy model files
        let blobsDir = base.appending(path: "blobs")
        if fm.fileExists(atPath: blobsDir.path(percentEncoded: false)) {
            let size = directorySize(blobsDir)
            if size > 0 {
                let accessed = lastAccessedDate(blobsDir)
                results.append(CacheEntry(
                    id: "ollama-blobs",
                    name: "Ollama Blobs",
                    sizeBytes: size,
                    source: .ollama,
                    lastAccessed: accessed,
                    path: blobsDir
                ))
            }
        }

        // manifests/ contains per-model manifest dirs: manifests/registry.ollama.ai/library/<model>
        let manifestsDir = base.appending(path: "manifests")
        let libraryDir = manifestsDir
            .appending(path: "registry.ollama.ai")
            .appending(path: "library")
        if fm.fileExists(atPath: libraryDir.path(percentEncoded: false)),
           let children = try? fm.contentsOfDirectory(
               at: libraryDir,
               includingPropertiesForKeys: [.isDirectoryKey],
               options: [.skipsHiddenFiles]
           ) {
            for child in children {
                guard (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
                let name = child.lastPathComponent
                let size = directorySize(child)
                guard size > 0 else { continue }
                let accessed = lastAccessedDate(child)
                results.append(CacheEntry(
                    id: "ollama-\(name)",
                    name: name,
                    sizeBytes: size,
                    source: .ollama,
                    lastAccessed: accessed,
                    path: child
                ))
            }
        }

        return results
    }

    /// HuggingFace hub caches models as `models--<org>--<name>` directories.
    private func scanHuggingFace(_ base: URL) -> [CacheEntry] {
        guard let children = try? fm.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [CacheEntry] = []
        for child in children {
            guard (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            let dirName = child.lastPathComponent
            // HF hub directories follow the pattern: models--<org>--<name>
            guard dirName.hasPrefix("models--") else { continue }

            let parts = dirName.dropFirst("models--".count).split(separator: "--", maxSplits: 1)
            let name: String
            if parts.count == 2 {
                name = "\(parts[0])/\(parts[1])"
            } else {
                name = String(parts.first ?? Substring(dirName))
            }

            let size = directorySize(child)
            guard size > 0 else { continue }
            let accessed = lastAccessedDate(child)

            results.append(CacheEntry(
                id: "hf-\(dirName)",
                name: name,
                sizeBytes: size,
                source: .huggingface,
                lastAccessed: accessed,
                path: child
            ))
        }
        return results
    }

    /// MLX cache — each subdirectory is a converted model.
    private func scanMLX(_ base: URL) -> [CacheEntry] {
        return scanGenericModelDirs(base, source: .mlx, idPrefix: "mlx")
    }

    /// Swoosh's own model directory.
    private func scanSwoosh(_ base: URL) -> [CacheEntry] {
        return scanGenericModelDirs(base, source: .swoosh, idPrefix: "swoosh")
    }

    /// Generic scanner for directories where each child dir is a model.
    private func scanGenericModelDirs(_ base: URL, source: CacheSource, idPrefix: String) -> [CacheEntry] {
        guard let children = try? fm.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [CacheEntry] = []
        for child in children {
            let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let name = child.lastPathComponent
            let size: UInt64
            if isDir {
                size = directorySize(child)
            } else {
                size = fileSize(child)
            }
            guard size > 0 else { continue }
            let accessed = lastAccessedDate(child)

            results.append(CacheEntry(
                id: "\(idPrefix)-\(name)",
                name: name,
                sizeBytes: size,
                source: source,
                lastAccessed: accessed,
                path: child
            ))
        }
        return results
    }

    // MARK: - File helpers

    /// Recursively compute total size of all files in a directory.
    private func directorySize(_ url: URL) -> UInt64 {
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize else { continue }
            total += UInt64(size)
        }
        return total
    }

    /// Size of a single file.
    private func fileSize(_ url: URL) -> UInt64 {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else { return 0 }
        return UInt64(size)
    }

    /// Last accessed (or modified) date for a path.
    private func lastAccessedDate(_ url: URL) -> Date {
        let keys: Set<URLResourceKey> = [.contentAccessDateKey, .contentModificationDateKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return .distantPast }
        return values.contentAccessDate ?? values.contentModificationDate ?? .distantPast
    }
}
