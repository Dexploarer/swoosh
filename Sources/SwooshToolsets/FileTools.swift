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
        let root = try await dependencies.fileAccess.resolveBookmark(id: input.rootBookmarkID)
        let (current, _, _) = try await dependencies.fileAccess.readFile(
            root: root,
            relativePath: input.relativePath,
            maxBytes: nil
        )
        let patched = try UnifiedDiffPatcher.apply(diff: input.unifiedDiff, to: current)
        let (_, backup) = try await dependencies.fileAccess.writeFile(
            root: root,
            relativePath: input.relativePath,
            content: patched,
            createBackup: input.createBackup
        )
        return FilePatchOutput(relativePath: input.relativePath, applied: true, backupPath: backup)
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

enum UnifiedDiffPatcher {
    static func apply(diff: String, to original: String) throws -> String {
        let hunks = try parse(diff: diff)
        guard !hunks.isEmpty else {
            throw ToolError.invalidInput("unifiedDiff contains no hunks")
        }

        let hadTrailingNewline = original.hasSuffix("\n")
        let originalLines = splitLines(original)
        var output: [String] = []
        var cursor = 0

        for hunk in hunks {
            let start = max(0, hunk.oldStart - 1)
            guard start >= cursor, start <= originalLines.count else {
                throw ToolError.invalidInput("hunk starts outside the target file")
            }
            output.append(contentsOf: originalLines[cursor..<start])
            cursor = start

            for line in hunk.lines {
                switch line.kind {
                case .context:
                    guard cursor < originalLines.count, originalLines[cursor] == line.text else {
                        throw ToolError.invalidInput("hunk context does not match target file")
                    }
                    output.append(line.text)
                    cursor += 1
                case .remove:
                    guard cursor < originalLines.count, originalLines[cursor] == line.text else {
                        throw ToolError.invalidInput("hunk removal does not match target file")
                    }
                    cursor += 1
                case .add:
                    output.append(line.text)
                }
            }
        }

        output.append(contentsOf: originalLines[cursor...])
        var patched = output.joined(separator: "\n")
        if hadTrailingNewline || diff.hasSuffix("\n") {
            patched += "\n"
        }
        return patched
    }

    private static func parse(diff: String) throws -> [Hunk] {
        var hunks: [Hunk] = []
        var current: Hunk?

        for rawLine in diff.components(separatedBy: "\n") {
            if rawLine.hasPrefix("--- ") || rawLine.hasPrefix("+++ ") || rawLine == #"\\ No newline at end of file"# {
                continue
            }
            if rawLine.hasPrefix("@@") {
                if let current { hunks.append(current) }
                current = try Hunk(header: rawLine)
                continue
            }
            guard current != nil else {
                if rawLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                throw ToolError.invalidInput("unifiedDiff has content before first hunk")
            }
            guard let marker = rawLine.first else { continue }
            let text = String(rawLine.dropFirst())
            guard var hunk = current else {
                throw ToolError.invalidInput("unifiedDiff has content before first hunk")
            }
            switch marker {
            case " ":
                hunk.lines.append(.init(kind: .context, text: text))
            case "-":
                hunk.lines.append(.init(kind: .remove, text: text))
            case "+":
                hunk.lines.append(.init(kind: .add, text: text))
            default:
                throw ToolError.invalidInput("invalid unified diff line: \(rawLine)")
            }
            current = hunk
        }

        if let current { hunks.append(current) }
        return hunks
    }

    private static func splitLines(_ text: String) -> [String] {
        var lines = text.components(separatedBy: "\n")
        if text.hasSuffix("\n") {
            lines.removeLast()
        }
        return lines
    }

    private struct Hunk {
        let oldStart: Int
        var lines: [HunkLine] = []

        init(header: String) throws {
            let pattern = #"@@ -(\d+)(?:,\d+)? \+\d+(?:,\d+)? @@"#
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(header.startIndex..<header.endIndex, in: header)
            guard
                let match = regex.firstMatch(in: header, range: range),
                let oldStartRange = Range(match.range(at: 1), in: header),
                let oldStart = Int(header[oldStartRange])
            else {
                throw ToolError.invalidInput("invalid unified diff hunk header: \(header)")
            }
            self.oldStart = oldStart
        }
    }

    private struct HunkLine {
        let kind: Kind
        let text: String

        enum Kind {
            case context
            case remove
            case add
        }
    }
}
