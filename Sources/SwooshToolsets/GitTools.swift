// SwooshToolsets/GitTools.swift — Git toolset implementations
// git.push is critical and shows preview. 
import Foundation
import SwooshTools

public struct GitStatusTool: SwooshTool {
    public typealias Input = GitRepoInput; public typealias Output = GitStatusOutput
    public static let name: ToolName = "git.status"; public static let displayName = "Git Status"
    public static let description = "Get repo status"; public static let permission = SwooshPermission.gitRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.git
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let root = try await dependencies.fileAccess.resolveBookmark(id: input.rootBookmarkID)
        let result = try await dependencies.processRunner.run(executable: "/usr/bin/git", arguments: ["status", "--porcelain", "-b"], workingDirectory: root, environment: nil)
        let lines = result.stdout.split(separator: "\n")
        let branch = lines.first.map { String($0.dropFirst(3).prefix(while: { $0 != "." })) } ?? "unknown"
        let changed = lines.dropFirst().map { GitChangedFile(path: String($0.dropFirst(3)), status: String($0.prefix(2))) }
        return GitStatusOutput(branch: branch, isClean: changed.isEmpty, changedFiles: changed)
    }
}

public struct GitDiffTool: SwooshTool {
    public typealias Input = GitDiffInput; public typealias Output = GitDiffOutput
    public static let name: ToolName = "git.diff"; public static let displayName = "Git Diff"
    public static let description = "Get diff"; public static let permission = SwooshPermission.gitRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.git
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let root = try await dependencies.fileAccess.resolveBookmark(id: input.rootBookmarkID)
        var args = ["diff"]; if input.staged { args.append("--cached") }
        if let paths = input.paths { args.append(contentsOf: ["--"] + paths) }
        let result = try await dependencies.processRunner.run(executable: "/usr/bin/git", arguments: args, workingDirectory: root, environment: nil)
        let filesChanged = result.stdout.split(separator: "\n").filter { $0.hasPrefix("diff --git") }.count
        return GitDiffOutput(diff: result.stdout, filesChanged: filesChanged)
    }
}

public struct GitLogTool: SwooshTool {
    public typealias Input = GitLogInput; public typealias Output = GitLogOutput
    public static let name: ToolName = "git.log"; public static let displayName = "Git Log"
    public static let description = "Read commit log"; public static let permission = SwooshPermission.gitRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.git
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let root = try await dependencies.fileAccess.resolveBookmark(id: input.rootBookmarkID)
        let limit = input.limit ?? 20
        let result = try await dependencies.processRunner.run(executable: "/usr/bin/git", arguments: ["log", "--oneline", "-n", "\(limit)"], workingDirectory: root, environment: nil)
        let commits = result.stdout.split(separator: "\n").map { line -> GitCommitEntry in
            let hash = String(line.prefix(7))
            let msg = String(line.dropFirst(8))
            return GitCommitEntry(hash: hash, shortHash: hash, author: "", date: Date(), message: msg)
        }
        return GitLogOutput(commits: commits)
    }
}

public struct GitBranchListTool: SwooshTool {
    public typealias Input = GitRepoInput; public typealias Output = GitBranchListOutput
    public static let name: ToolName = "git.branch_list"; public static let displayName = "List Branches"
    public static let description = "List branches"; public static let permission = SwooshPermission.gitRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.git
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let root = try await dependencies.fileAccess.resolveBookmark(id: input.rootBookmarkID)
        let result = try await dependencies.processRunner.run(executable: "/usr/bin/git", arguments: ["branch", "-a"], workingDirectory: root, environment: nil)
        var current = ""
        let branches = result.stdout.split(separator: "\n").map { line -> GitBranch in
            let isCurrent = line.hasPrefix("*")
            let name = String(line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "* ", with: ""))
            if isCurrent { current = name }
            return GitBranch(name: name, isCurrent: isCurrent, isRemote: name.hasPrefix("remotes/"))
        }
        return GitBranchListOutput(branches: branches, currentBranch: current)
    }
}

public struct GitApplyPatchTool: SwooshTool {
    public typealias Input = GitApplyPatchInput; public typealias Output = GitApplyPatchOutput
    public static let name: ToolName = "git.apply_patch"; public static let displayName = "Apply Patch"
    public static let description = "Apply patch"; public static let permission = SwooshPermission.gitWrite
    public static let risk = ToolRisk.high; public static let approval = ApprovalPolicy.askEveryTime; public static let toolset = ToolsetID.git
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        GitApplyPatchOutput(applied: false, output: "Not yet implemented")
    }
}

public struct GitCommitTool: SwooshTool {
    public typealias Input = GitCommitInput; public typealias Output = GitCommitOutput
    public static let name: ToolName = "git.commit"; public static let displayName = "Git Commit"
    public static let description = "Create commit"; public static let permission = SwooshPermission.gitWrite
    public static let risk = ToolRisk.high; public static let approval = ApprovalPolicy.askEveryTime; public static let toolset = ToolsetID.git
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let root = try await dependencies.fileAccess.resolveBookmark(id: input.rootBookmarkID)
        if !input.includePaths.isEmpty {
            _ = try await dependencies.processRunner.run(executable: "/usr/bin/git", arguments: ["add"] + input.includePaths, workingDirectory: root, environment: nil)
        }
        let result = try await dependencies.processRunner.run(executable: "/usr/bin/git", arguments: ["commit", "-m", input.message], workingDirectory: root, environment: nil)
        let hash = result.stdout.split(separator: " ").dropFirst().first.map(String.init) ?? "unknown"
        return GitCommitOutput(commitHash: hash, message: input.message)
    }
}

public struct GitCheckoutTool: SwooshTool {
    public typealias Input = GitCheckoutInput; public typealias Output = GitCheckoutOutput
    public static let name: ToolName = "git.checkout"; public static let displayName = "Git Checkout"
    public static let description = "Checkout branch"; public static let permission = SwooshPermission.gitWrite
    public static let risk = ToolRisk.high; public static let approval = ApprovalPolicy.askEveryTime; public static let toolset = ToolsetID.git
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let root = try await dependencies.fileAccess.resolveBookmark(id: input.rootBookmarkID)
        var args = ["checkout"]; if input.createNew { args.append("-b") }; args.append(input.branch)
        _ = try await dependencies.processRunner.run(executable: "/usr/bin/git", arguments: args, workingDirectory: root, environment: nil)
        return GitCheckoutOutput(branch: input.branch, created: input.createNew)
    }
}

public struct GitPushTool: SwooshTool {
    public typealias Input = GitPushInput; public typealias Output = GitPushOutput
    public static let name: ToolName = "git.push"; public static let displayName = "Git Push"
    public static let description = "Push to remote (critical, shows preview)"; public static let permission = SwooshPermission.gitWrite
    public static let risk = ToolRisk.critical; public static let approval = ApprovalPolicy.askEveryTime; public static let toolset = ToolsetID.git
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let root = try await dependencies.fileAccess.resolveBookmark(id: input.rootBookmarkID)
        // Preview
        let logResult = try await dependencies.processRunner.run(executable: "/usr/bin/git", arguments: ["log", "--oneline", "@{u}..HEAD"], workingDirectory: root, environment: nil)
        let commitCount = logResult.stdout.split(separator: "\n").count
        var args = ["push", input.remote]; if let b = input.branch { args.append(b) }
        if input.force { args.append("--force") }
        let result = try await dependencies.processRunner.run(executable: "/usr/bin/git", arguments: args, workingDirectory: root, environment: nil)
        return GitPushOutput(remote: input.remote, branch: input.branch ?? "HEAD", commitCount: commitCount, diffSummary: logResult.stdout, output: result.stdout + result.stderr)
    }
}
