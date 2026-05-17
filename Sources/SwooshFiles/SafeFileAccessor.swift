// SwooshFiles/SafeFileAccessor.swift — Concrete file access with safety (0.4C)
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

        return try listRecursive(
            baseURL: URL(fileURLWithPath: approvedRoot.absolutePath),
            currentURL: targetURL,
            includeHidden: includeHidden,
            maxDepth: maxDepth,
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
        // Disabled in 0.4C
        throw FileAccessError.writeNotAllowed
    }

    public func searchFiles(
        root: URL,
        query: String,
        filePattern: String?,
        maxResults: Int?
    ) async throws -> [FileSearchMatch] {
        let approvedRoot = try await findApprovedRoot(for: root)
        try pathResolver.validateAccess(root: approvedRoot, write: false)
        let rootURL = URL(fileURLWithPath: approvedRoot.absolutePath)
        let limit = maxResults ?? 50

        var results: [FileSearchMatch] = []
        let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            guard results.count < limit else { break }

            let relativePath = fileURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
            if sensitivePolicy.shouldSkip(path: relativePath) {
                enumerator?.skipDescendants()
                continue
            }

            // Match file pattern if specified
            if let pattern = filePattern {
                let name = fileURL.lastPathComponent
                if !matchGlob(name: name, pattern: pattern) { continue }
            }

            guard let isFile = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile,
                  isFile else { continue }

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
            let relativePath = item.path.replacingOccurrences(of: baseURL.path + "/", with: "")

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

    private func matchGlob(name: String, pattern: String) -> Bool {
        // Simple glob: *.swift → name ends with .swift
        if pattern.hasPrefix("*.") {
            let ext = String(pattern.dropFirst(2))
            return name.hasSuffix("." + ext)
        }
        return name == pattern
    }
}
