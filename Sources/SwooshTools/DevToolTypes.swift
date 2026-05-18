// SwooshTools/DevToolTypes.swift — Input/Output types for File, Git, and Swift dev toolsets.
//
// File tools operate inside approved folder bookmarks only.
// Git tools enforce preview before destructive operations.
// Swift dev tools capture diagnostics from build/test.

import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - File tools
// ═══════════════════════════════════════════════════════════════════

// ── file.list ─────────────────────────────────────────────────────

public struct FileListInput: Codable, Sendable {
    public let rootBookmarkID: String
    public let relativePath: String?
    public let includeHidden: Bool
    public let maxDepth: Int

    public init(
        rootBookmarkID: String,
        relativePath: String? = nil,
        includeHidden: Bool = false,
        maxDepth: Int = 3
    ) {
        self.rootBookmarkID = rootBookmarkID
        self.relativePath = relativePath
        self.includeHidden = includeHidden
        self.maxDepth = maxDepth
    }
}

public struct FileListOutput: Codable, Sendable {
    public let entries: [FileEntry]

    public init(entries: [FileEntry]) {
        self.entries = entries
    }
}

public struct FileEntry: Codable, Sendable {
    public let relativePath: String
    public let kind: FileKind
    public let byteSize: Int64?
    public let modifiedAt: Date?

    public init(relativePath: String, kind: FileKind, byteSize: Int64? = nil, modifiedAt: Date? = nil) {
        self.relativePath = relativePath
        self.kind = kind
        self.byteSize = byteSize
        self.modifiedAt = modifiedAt
    }
}

public enum FileKind: String, Codable, Sendable {
    case file
    case directory
    case symlink
    case other
}

// ── file.read ─────────────────────────────────────────────────────

public struct FileReadInput: Codable, Sendable {
    public let rootBookmarkID: String
    public let relativePath: String
    public let maxBytes: Int?

    public init(rootBookmarkID: String, relativePath: String, maxBytes: Int? = nil) {
        self.rootBookmarkID = rootBookmarkID
        self.relativePath = relativePath
        self.maxBytes = maxBytes
    }
}

public struct FileReadOutput: Codable, Sendable {
    public let relativePath: String
    public let content: String
    public let truncated: Bool
    public let redactionReport: RedactionReport?

    public init(
        relativePath: String,
        content: String,
        truncated: Bool = false,
        redactionReport: RedactionReport? = nil
    ) {
        self.relativePath = relativePath
        self.content = content
        self.truncated = truncated
        self.redactionReport = redactionReport
    }
}

public struct RedactionReport: Codable, Sendable {
    public let redactedPatterns: [String]
    public let redactionCount: Int

    public init(redactedPatterns: [String], redactionCount: Int) {
        self.redactedPatterns = redactedPatterns
        self.redactionCount = redactionCount
    }
}

// ── file.search ───────────────────────────────────────────────────

public struct FileSearchInput: Codable, Sendable {
    public let rootBookmarkID: String
    public let query: String
    public let filePattern: String?
    public let maxResults: Int?

    public init(rootBookmarkID: String, query: String, filePattern: String? = nil, maxResults: Int? = nil) {
        self.rootBookmarkID = rootBookmarkID
        self.query = query
        self.filePattern = filePattern
        self.maxResults = maxResults
    }
}

public struct FileSearchOutput: Codable, Sendable {
    public let matches: [FileSearchMatch]

    public init(matches: [FileSearchMatch]) {
        self.matches = matches
    }
}

public struct FileSearchMatch: Codable, Sendable {
    public let relativePath: String
    public let lineNumber: Int?
    public let lineContent: String?

    public init(relativePath: String, lineNumber: Int? = nil, lineContent: String? = nil) {
        self.relativePath = relativePath
        self.lineNumber = lineNumber
        self.lineContent = lineContent
    }
}

// ── file.write ────────────────────────────────────────────────────

public struct FileWriteInput: Codable, Sendable {
    public let rootBookmarkID: String
    public let relativePath: String
    public let content: String
    public let createBackup: Bool

    public init(rootBookmarkID: String, relativePath: String, content: String, createBackup: Bool = true) {
        self.rootBookmarkID = rootBookmarkID
        self.relativePath = relativePath
        self.content = content
        self.createBackup = createBackup
    }
}

public struct FileWriteOutput: Codable, Sendable {
    public let relativePath: String
    public let bytesWritten: Int64
    public let backupPath: String?

    public init(relativePath: String, bytesWritten: Int64, backupPath: String? = nil) {
        self.relativePath = relativePath
        self.bytesWritten = bytesWritten
        self.backupPath = backupPath
    }
}

// ── file.patch ────────────────────────────────────────────────────

public struct FilePatchInput: Codable, Sendable {
    public let rootBookmarkID: String
    public let relativePath: String
    public let unifiedDiff: String
    public let createBackup: Bool

    public init(rootBookmarkID: String, relativePath: String, unifiedDiff: String, createBackup: Bool = true) {
        self.rootBookmarkID = rootBookmarkID
        self.relativePath = relativePath
        self.unifiedDiff = unifiedDiff
        self.createBackup = createBackup
    }
}

public struct FilePatchOutput: Codable, Sendable {
    public let relativePath: String
    public let applied: Bool
    public let backupPath: String?

    public init(relativePath: String, applied: Bool, backupPath: String? = nil) {
        self.relativePath = relativePath
        self.applied = applied
        self.backupPath = backupPath
    }
}

// ── file.delete ───────────────────────────────────────────────────

public struct FileDeleteInput: Codable, Sendable {
    public let rootBookmarkID: String
    public let relativePath: String
    public let confirmDeletion: Bool

    public init(rootBookmarkID: String, relativePath: String, confirmDeletion: Bool = false) {
        self.rootBookmarkID = rootBookmarkID
        self.relativePath = relativePath
        self.confirmDeletion = confirmDeletion
    }
}

public struct FileDeleteOutput: Codable, Sendable {
    public let relativePath: String
    public let deleted: Bool

    public init(relativePath: String, deleted: Bool) {
        self.relativePath = relativePath
        self.deleted = deleted
    }
}

// ═══════════════════════════════════════════════════════════════════
