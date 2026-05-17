// SwooshToolsets/FileTools.swift — File toolset implementations
// file.delete is disabled by default (critical + disabled approval).
import Foundation
import SwooshTools

public struct FileListTool: SwooshTool {
    public typealias Input = FileListInput; public typealias Output = FileListOutput
    public static let name: ToolName = "file.list"; public static let displayName = "List Files"
    public static let description = "List files under approved folder"; public static let permission = SwooshPermission.fileRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.files
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let root = try await dependencies.fileAccess.resolveBookmark(id: input.rootBookmarkID)
        let entries = try await dependencies.fileAccess.listDirectory(root: root, relativePath: input.relativePath, includeHidden: input.includeHidden, maxDepth: input.maxDepth)
        return FileListOutput(entries: entries)
    }
}

public struct FileReadTool: SwooshTool {
    public typealias Input = FileReadInput; public typealias Output = FileReadOutput
    public static let name: ToolName = "file.read"; public static let displayName = "Read File"
    public static let description = "Read approved file"; public static let permission = SwooshPermission.fileRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.files
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let root = try await dependencies.fileAccess.resolveBookmark(id: input.rootBookmarkID)
        let (content, truncated, redaction) = try await dependencies.fileAccess.readFile(root: root, relativePath: input.relativePath, maxBytes: input.maxBytes)
        return FileReadOutput(relativePath: input.relativePath, content: content, truncated: truncated, redactionReport: redaction)
    }
}

public struct FileSearchTool: SwooshTool {
    public typealias Input = FileSearchInput; public typealias Output = FileSearchOutput
    public static let name: ToolName = "file.search"; public static let displayName = "Search Files"
    public static let description = "Search approved folder"; public static let permission = SwooshPermission.fileRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.files
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let root = try await dependencies.fileAccess.resolveBookmark(id: input.rootBookmarkID)
        let matches = try await dependencies.fileAccess.searchFiles(root: root, query: input.query, filePattern: input.filePattern, maxResults: input.maxResults)
        return FileSearchOutput(matches: matches)
    }
}

public struct FileWriteTool: SwooshTool {
    public typealias Input = FileWriteInput; public typealias Output = FileWriteOutput
    public static let name: ToolName = "file.write"; public static let displayName = "Write File"
    public static let description = "Write file"; public static let permission = SwooshPermission.fileWrite
    public static let risk = ToolRisk.high; public static let approval = ApprovalPolicy.askEveryTime; public static let toolset = ToolsetID.files
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let root = try await dependencies.fileAccess.resolveBookmark(id: input.rootBookmarkID)
        let (bytes, backup) = try await dependencies.fileAccess.writeFile(root: root, relativePath: input.relativePath, content: input.content, createBackup: input.createBackup)
        return FileWriteOutput(relativePath: input.relativePath, bytesWritten: bytes, backupPath: backup)
    }
}

public struct FilePatchTool: SwooshTool {
    public typealias Input = FilePatchInput; public typealias Output = FilePatchOutput
    public static let name: ToolName = "file.patch"; public static let displayName = "Patch File"
    public static let description = "Apply patch"; public static let permission = SwooshPermission.fileWrite
    public static let risk = ToolRisk.high; public static let approval = ApprovalPolicy.askEveryTime; public static let toolset = ToolsetID.files
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        FilePatchOutput(relativePath: input.relativePath, applied: false, backupPath: nil)
    }
}

public struct FileDeleteTool: SwooshTool {
    public typealias Input = FileDeleteInput; public typealias Output = FileDeleteOutput
    public static let name: ToolName = "file.delete"; public static let displayName = "Delete File"
    public static let description = "Delete file (disabled by default)"; public static let permission = SwooshPermission.fileWrite
    public static let risk = ToolRisk.critical; public static let approval = ApprovalPolicy.disabled; public static let toolset = ToolsetID.files
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        throw ToolError.disabled("file.delete is disabled by default")
    }
}
