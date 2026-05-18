// SwooshTools/GitToolTypes.swift — Git tool input/output types
import Foundation

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
