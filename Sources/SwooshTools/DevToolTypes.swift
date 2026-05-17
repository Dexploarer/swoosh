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
// MARK: - Git tools
// ═══════════════════════════════════════════════════════════════════

// ── Shared git repo input ─────────────────────────────────────────

public struct GitRepoInput: Codable, Sendable {
    public let rootBookmarkID: String

    public init(rootBookmarkID: String) {
        self.rootBookmarkID = rootBookmarkID
    }
}

// ── git.status ────────────────────────────────────────────────────

public struct GitStatusOutput: Codable, Sendable {
    public let branch: String
    public let isClean: Bool
    public let changedFiles: [GitChangedFile]

    public init(branch: String, isClean: Bool, changedFiles: [GitChangedFile]) {
        self.branch = branch
        self.isClean = isClean
        self.changedFiles = changedFiles
    }
}

public struct GitChangedFile: Codable, Sendable {
    public let path: String
    public let status: String

    public init(path: String, status: String) {
        self.path = path
        self.status = status
    }
}

// ── git.diff ──────────────────────────────────────────────────────

public struct GitDiffInput: Codable, Sendable {
    public let rootBookmarkID: String
    public let staged: Bool
    public let paths: [String]?

    public init(rootBookmarkID: String, staged: Bool = false, paths: [String]? = nil) {
        self.rootBookmarkID = rootBookmarkID
        self.staged = staged
        self.paths = paths
    }
}

public struct GitDiffOutput: Codable, Sendable {
    public let diff: String
    public let filesChanged: Int

    public init(diff: String, filesChanged: Int) {
        self.diff = diff
        self.filesChanged = filesChanged
    }
}

// ── git.log ───────────────────────────────────────────────────────

public struct GitLogInput: Codable, Sendable {
    public let rootBookmarkID: String
    public let limit: Int?
    public let since: Date?

    public init(rootBookmarkID: String, limit: Int? = nil, since: Date? = nil) {
        self.rootBookmarkID = rootBookmarkID
        self.limit = limit
        self.since = since
    }
}

public struct GitLogOutput: Codable, Sendable {
    public let commits: [GitCommitEntry]

    public init(commits: [GitCommitEntry]) {
        self.commits = commits
    }
}

public struct GitCommitEntry: Codable, Sendable {
    public let hash: String
    public let shortHash: String
    public let author: String
    public let date: Date
    public let message: String

    public init(hash: String, shortHash: String, author: String, date: Date, message: String) {
        self.hash = hash
        self.shortHash = shortHash
        self.author = author
        self.date = date
        self.message = message
    }
}

// ── git.branch_list ───────────────────────────────────────────────

public struct GitBranchListOutput: Codable, Sendable {
    public let branches: [GitBranch]
    public let currentBranch: String

    public init(branches: [GitBranch], currentBranch: String) {
        self.branches = branches
        self.currentBranch = currentBranch
    }
}

public struct GitBranch: Codable, Sendable {
    public let name: String
    public let isCurrent: Bool
    public let isRemote: Bool

    public init(name: String, isCurrent: Bool, isRemote: Bool = false) {
        self.name = name
        self.isCurrent = isCurrent
        self.isRemote = isRemote
    }
}

// ── git.apply_patch ───────────────────────────────────────────────

public struct GitApplyPatchInput: Codable, Sendable {
    public let rootBookmarkID: String
    public let unifiedDiff: String
    public let check: Bool

    public init(rootBookmarkID: String, unifiedDiff: String, check: Bool = false) {
        self.rootBookmarkID = rootBookmarkID
        self.unifiedDiff = unifiedDiff
        self.check = check
    }
}

public struct GitApplyPatchOutput: Codable, Sendable {
    public let applied: Bool
    public let output: String

    public init(applied: Bool, output: String) {
        self.applied = applied
        self.output = output
    }
}

// ── git.commit ────────────────────────────────────────────────────

public struct GitCommitInput: Codable, Sendable {
    public let rootBookmarkID: String
    public let message: String
    public let includePaths: [String]

    public init(rootBookmarkID: String, message: String, includePaths: [String] = []) {
        self.rootBookmarkID = rootBookmarkID
        self.message = message
        self.includePaths = includePaths
    }
}

public struct GitCommitOutput: Codable, Sendable {
    public let commitHash: String
    public let message: String

    public init(commitHash: String, message: String) {
        self.commitHash = commitHash
        self.message = message
    }
}

// ── git.checkout ──────────────────────────────────────────────────

public struct GitCheckoutInput: Codable, Sendable {
    public let rootBookmarkID: String
    public let branch: String
    public let createNew: Bool

    public init(rootBookmarkID: String, branch: String, createNew: Bool = false) {
        self.rootBookmarkID = rootBookmarkID
        self.branch = branch
        self.createNew = createNew
    }
}

public struct GitCheckoutOutput: Codable, Sendable {
    public let branch: String
    public let created: Bool

    public init(branch: String, created: Bool) {
        self.branch = branch
        self.created = created
    }
}

// ── git.push ──────────────────────────────────────────────────────

public struct GitPushInput: Codable, Sendable {
    public let rootBookmarkID: String
    public let remote: String
    public let branch: String?
    public let force: Bool

    public init(rootBookmarkID: String, remote: String = "origin", branch: String? = nil, force: Bool = false) {
        self.rootBookmarkID = rootBookmarkID
        self.remote = remote
        self.branch = branch
        self.force = force
    }
}

public struct GitPushOutput: Codable, Sendable {
    public let remote: String
    public let branch: String
    public let commitCount: Int
    public let diffSummary: String
    public let output: String

    public init(remote: String, branch: String, commitCount: Int, diffSummary: String, output: String) {
        self.remote = remote
        self.branch = branch
        self.commitCount = commitCount
        self.diffSummary = diffSummary
        self.output = output
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Swift developer tools
// ═══════════════════════════════════════════════════════════════════

// ── swift.package_describe ────────────────────────────────────────

public struct SwiftPackageDescribeInput: Codable, Sendable {
    public let rootBookmarkID: String

    public init(rootBookmarkID: String) {
        self.rootBookmarkID = rootBookmarkID
    }
}

public struct SwiftPackageDescribeOutput: Codable, Sendable {
    public let packageName: String?
    public let products: [String]
    public let targets: [SwiftTarget]
    public let dependencies: [String]

    public init(packageName: String?, products: [String], targets: [SwiftTarget], dependencies: [String]) {
        self.packageName = packageName
        self.products = products
        self.targets = targets
        self.dependencies = dependencies
    }
}

public struct SwiftTarget: Codable, Sendable {
    public let name: String
    public let type: String

    public init(name: String, type: String) {
        self.name = name
        self.type = type
    }
}

// ── swift.build ───────────────────────────────────────────────────

public struct SwiftBuildInput: Codable, Sendable {
    public let rootBookmarkID: String
    public let configuration: SwiftBuildConfiguration
    public let extraArguments: [String]

    public init(rootBookmarkID: String, configuration: SwiftBuildConfiguration = .debug, extraArguments: [String] = []) {
        self.rootBookmarkID = rootBookmarkID
        self.configuration = configuration
        self.extraArguments = extraArguments
    }
}

public enum SwiftBuildConfiguration: String, Codable, Sendable {
    case debug
    case release
}

public struct SwiftBuildOutput: Codable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let diagnostics: [BuildDiagnostic]

    public init(exitCode: Int32, stdout: String, stderr: String, diagnostics: [BuildDiagnostic]) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.diagnostics = diagnostics
    }
}

public struct BuildDiagnostic: Codable, Sendable {
    public let severity: DiagnosticSeverity
    public let message: String
    public let file: String?
    public let line: Int?
    public let column: Int?

    public init(severity: DiagnosticSeverity, message: String, file: String? = nil, line: Int? = nil, column: Int? = nil) {
        self.severity = severity
        self.message = message
        self.file = file
        self.line = line
        self.column = column
    }
}

public enum DiagnosticSeverity: String, Codable, Sendable {
    case error
    case warning
    case note
}

// ── swift.test ────────────────────────────────────────────────────

public struct SwiftTestInput: Codable, Sendable {
    public let rootBookmarkID: String
    public let filter: String?
    public let extraArguments: [String]

    public init(rootBookmarkID: String, filter: String? = nil, extraArguments: [String] = []) {
        self.rootBookmarkID = rootBookmarkID
        self.filter = filter
        self.extraArguments = extraArguments
    }
}

public struct SwiftTestOutput: Codable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let testsPassed: Int
    public let testsFailed: Int
    public let diagnostics: [BuildDiagnostic]

    public init(exitCode: Int32, stdout: String, stderr: String, testsPassed: Int, testsFailed: Int, diagnostics: [BuildDiagnostic]) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.testsPassed = testsPassed
        self.testsFailed = testsFailed
        self.diagnostics = diagnostics
    }
}

// ── swift.format_check ────────────────────────────────────────────

public struct SwiftFormatCheckInput: Codable, Sendable {
    public let rootBookmarkID: String
    public let paths: [String]?

    public init(rootBookmarkID: String, paths: [String]? = nil) {
        self.rootBookmarkID = rootBookmarkID
        self.paths = paths
    }
}

public struct SwiftFormatCheckOutput: Codable, Sendable {
    public let isFormatted: Bool
    public let violations: [FormatViolation]

    public init(isFormatted: Bool, violations: [FormatViolation]) {
        self.isFormatted = isFormatted
        self.violations = violations
    }
}

public struct FormatViolation: Codable, Sendable {
    public let file: String
    public let line: Int
    public let description: String

    public init(file: String, line: Int, description: String) {
        self.file = file
        self.line = line
        self.description = description
    }
}

// ── swift.diagnostics ─────────────────────────────────────────────

public struct SwiftDiagnosticsInput: Codable, Sendable {
    public let rootBookmarkID: String

    public init(rootBookmarkID: String) {
        self.rootBookmarkID = rootBookmarkID
    }
}

public struct SwiftDiagnosticsOutput: Codable, Sendable {
    public let diagnostics: [BuildDiagnostic]
    public let fromLastBuild: Bool

    public init(diagnostics: [BuildDiagnostic], fromLastBuild: Bool) {
        self.diagnostics = diagnostics
        self.fromLastBuild = fromLastBuild
    }
}
