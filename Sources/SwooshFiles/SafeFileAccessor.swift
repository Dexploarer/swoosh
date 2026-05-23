// SwooshFiles/SafeFileAccessor.swift — Concrete file access with safety (0.4D)
//
// Implements FileAccessing from SwooshTools.
// Every operation validates paths, checks sensitivity, enforces size limits.

import Foundation
import SwooshTools

public struct SafeFileAccessor: FileAccessing, Sendable {
    public let rootStore: any ApprovedRootStore
    public let pathResolver: SafePathResolver
    public let sensitivePolicy: SensitiveFilePolicy
    public let maxFileSize: Int64

    /// Hard cap on recursive directory walks. A caller passing
    /// `maxDepth: 9999` still walks no deeper than this. Defense in
    /// depth — `listRecursive` is recursive without TCO.
    public static let maxRecursiveDepth: Int = 32

    public init(
        rootStore: any ApprovedRootStore,
        pathResolver: SafePathResolver = SafePathResolver(),
        sensitivePolicy: SensitiveFilePolicy = SensitiveFilePolicy(),
        maxFileSize: Int64 = 10_000_000 // 10MB
    ) {
        self.rootStore = rootStore
        self.pathResolver = pathResolver
        self.sensitivePolicy = sensitivePolicy
        self.maxFileSize = maxFileSize
    }

    // MARK: - FileAccessing conformance

    public func resolveBookmark(id: String) async throws -> URL {
        guard let root = await rootStore.get(id: id) else {
            throw FileAccessError.rootNotApproved
        }
        // Prefer the security-scoped bookmark when one was stored. Stale
        // bookmarks fall through to the absolute path so a moved/renamed
        // root still resolves (matches the 0.4C behaviour for callers
        // that never set bookmarkData).
        if let data = root.bookmarkData {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), !isStale {
                return url
            }
        }
        return URL(fileURLWithPath: root.absolutePath)
    }

    public func listDirectory(
        root: URL,
        relativePath: String?,
        includeHidden: Bool,
        maxDepth: Int
    ) async throws -> [FileEntry] {
        let approvedRoot = try await findApprovedRoot(for: root)
        try pathResolver.validateAccess(root: approvedRoot, write: false)

        let targetURL: URL
        if let rel = relativePath {
            targetURL = try pathResolver.resolve(root: approvedRoot, relativePath: rel)
        } else {
            targetURL = URL(fileURLWithPath: approvedRoot.absolutePath)
        }

        let safeDepth = min(max(maxDepth, 0), Self.maxRecursiveDepth)
        // Standardize so `/tmp/...` and `/private/tmp/...` (macOS
        // symlink) compare equal under prefix strip.
        return try listRecursive(
            baseURL: URL(fileURLWithPath: approvedRoot.absolutePath).standardizedFileURL,
            currentURL: targetURL.standardizedFileURL,
            includeHidden: includeHidden,
            maxDepth: safeDepth,
            currentDepth: 0
        )
    }

    public func readFile(
        root: URL,
        relativePath: String,
        maxBytes: Int?
    ) async throws -> (content: String, truncated: Bool, redaction: RedactionReport?) {
        let approvedRoot = try await findApprovedRoot(for: root)
        try pathResolver.validateAccess(root: approvedRoot, write: false)
        let fileURL = try pathResolver.resolve(root: approvedRoot, relativePath: relativePath)

        // Sensitive file check
        if sensitivePolicy.shouldBlock(path: relativePath) {
            throw FileAccessError.sensitiveFileBlocked(relativePath)
        }

        // Size check
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = (attrs[.size] as? Int64) ?? 0
        if fileSize > maxFileSize {
            throw FileAccessError.fileTooLarge(fileSize)
        }

        var data = try Data(contentsOf: fileURL)
        var truncated = false
        if let max = maxBytes, data.count > max {
            data = data.prefix(max)
            truncated = true
        }

        guard let content = String(data: data, encoding: .utf8) else {
            throw FileAccessError.unsupportedEncoding
        }

        return (content, truncated, nil)
    }

    public func writeFile(
        root: URL,
        relativePath: String,
        content: String,
        createBackup: Bool
    ) async throws -> (bytesWritten: Int64, backupPath: String?) {
        let approvedRoot = try await findApprovedRoot(for: root)
        try pathResolver.validateAccess(root: approvedRoot, write: true)
        let fileURL = try pathResolver.resolve(root: approvedRoot, relativePath: relativePath)

        if sensitivePolicy.shouldBlock(path: relativePath) {
            throw FileAccessError.sensitiveFileBlocked(relativePath)
        }

        var backupPath: String? = nil
        if createBackup && FileManager.default.fileExists(atPath: fileURL.path) {
            let backupURL = fileURL.appendingPathExtension("swoosh-backup")
            try? FileManager.default.copyItem(at: fileURL, to: backupURL)
            backupPath = backupURL.lastPathComponent
        }

        guard let data = content.data(using: .utf8) else {
            throw FileAccessError.unsupportedEncoding
        }
        try data.write(to: fileURL)

        return (Int64(data.count), backupPath)
    }

    public func deleteFile(root: URL, relativePath: String) async throws {
        // Deletion is intentionally not exposed through the file
        // toolset. Distinguish from `writeNotAllowed` so a UI can
        // surface "delete is unsupported" rather than "this root is
        // read-only".
        throw FileAccessError.deletionUnsupported
    }

    public func searchFiles(
        root: URL,
        query: String,
        filePattern: String?,
        maxResults: Int?
    ) async throws -> [FileSearchMatch] {
        let approvedRoot = try await findApprovedRoot(for: root)
        try pathResolver.validateAccess(root: approvedRoot, write: false)
        // Standardize so `/tmp/...` and `/private/tmp/...` (macOS
        // symlink) compare equal under prefix strip.
        let rootURL = URL(fileURLWithPath: approvedRoot.absolutePath).standardizedFileURL
        let limit = maxResults ?? 50

        var results: [FileSearchMatch] = []
        let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            guard results.count < limit else { break }

            let relativePath = relativise(fileURL.standardizedFileURL.path, under: rootURL.path)
            if sensitivePolicy.shouldSkip(path: relativePath) {
                enumerator?.skipDescendants()
                continue
            }

            // Match file pattern if specified
            if let pattern = filePattern {
                let name = fileURL.lastPathComponent
                if !matchGlob(name: name, pattern: pattern) { continue }
            }

            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }

            // Skip files above the size budget — mirrors `readFile`'s
            // `fileTooLarge` guard. Without this, a 1 GB blob in the
            // tree would be loaded into memory just to be skipped.
            if let size = values.fileSize, Int64(size) > maxFileSize { continue }

            // Search content
            guard let data = try? Data(contentsOf: fileURL),
                  let content = String(data: data, encoding: .utf8) else { continue }

            let lines = content.components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() {
                guard results.count < limit else { break }
                if line.localizedCaseInsensitiveContains(query) {
                    results.append(FileSearchMatch(
                        relativePath: relativePath,
                        lineNumber: index + 1,
                        lineContent: String(line.prefix(200))
                    ))
                }
            }
        }

        return results
    }

    // MARK: - Helpers

    private func findApprovedRoot(for rootURL: URL) async throws -> ApprovedRoot {
        let path = rootURL.standardizedFileURL.path
        guard let root = await rootStore.findByPath(path) else {
            throw FileAccessError.rootNotApproved
        }
        return root
    }

    private func listRecursive(
        baseURL: URL,
        currentURL: URL,
        includeHidden: Bool,
        maxDepth: Int,
        currentDepth: Int
    ) throws -> [FileEntry] {
        guard currentDepth <= maxDepth else { return [] }

        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]

        guard let contents = try? fm.contentsOfDirectory(at: currentURL, includingPropertiesForKeys: keys, options: options) else {
            return []
        }

        var entries: [FileEntry] = []
        for item in contents {
            let relativePath = relativise(item.standardizedFileURL.path, under: baseURL.path)

            let isSensitive = sensitivePolicy.shouldSkip(path: relativePath)
            let values = try? item.resourceValues(forKeys: Set(keys))
            let isDir = values?.isDirectory ?? false

            let kind: FileKind = isDir ? .directory : .file
            let entry = FileEntry(
                relativePath: relativePath,
                kind: kind,
                byteSize: Int64(values?.fileSize ?? 0),
                modifiedAt: values?.contentModificationDate
            )
            entries.append(entry)

            if isDir && !isSensitive && currentDepth < maxDepth {
                let children = try listRecursive(
                    baseURL: baseURL,
                    currentURL: item,
                    includeHidden: includeHidden,
                    maxDepth: maxDepth,
                    currentDepth: currentDepth + 1
                )
                entries.append(contentsOf: children)
            }
        }

        return entries
    }

    /// Strict prefix-strip — returns the portion of `fullPath` after
    /// `prefix/`, or `fullPath` unchanged if it doesn't actually live
    /// under that prefix. Previously `replacingOccurrences` was used and
    /// silently matched substrings (e.g. `/var/X/` was found inside
    /// `/private/var/X/file`, leaving `/privatefile`).
    func relativise(_ fullPath: String, under prefix: String) -> String {
        let normalized = prefix.hasSuffix("/") ? prefix : prefix + "/"
        if fullPath.hasPrefix(normalized) {
            return String(fullPath.dropFirst(normalized.count))
        }
        if fullPath == prefix {
            return ""
        }
        return fullPath
    }

    /// Single-segment glob matcher. Supported forms:
    ///   • exact          — `README.md`
    ///   • prefix         — `Tests*`
    ///   • suffix         — `*.swift` (and the historical alias `*.ext`)
    ///   • contains       — `*Foo*`
    ///   • prefix+suffix  — `Tests*.swift`
    ///
    /// Does NOT support `?`, character classes, or recursive `**`. Path
    /// separators are not part of the input — the caller already split
    /// off the basename.
    func matchGlob(name: String, pattern: String) -> Bool {
        // Fast path: no wildcard at all.
        guard pattern.contains("*") else { return name == pattern }

        let starts = pattern.hasPrefix("*")
        let ends   = pattern.hasSuffix("*")
        let trimmed = pattern.trimmingCharacters(in: CharacterSet(charactersIn: "*"))

        // "*" or "**" — matches everything.
        if trimmed.isEmpty { return true }

        // "*Foo*" — contains.
        if starts && ends { return name.contains(trimmed) }
        // "*Foo" / "*.ext" — suffix.
        if starts { return name.hasSuffix(trimmed) }
        // "Foo*" — prefix.
        if ends { return name.hasPrefix(trimmed) }

        // Embedded "*" e.g. "Tests*.swift" — split on the single star
        // and require prefix + suffix. Only one "*" is supported.
        let parts = pattern.split(separator: "*", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let prefix = String(parts[0])
        let suffix = String(parts[1])
        guard name.count >= prefix.count + suffix.count else { return false }
        return name.hasPrefix(prefix) && name.hasSuffix(suffix)
    }
}
