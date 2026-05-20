// SwooshToolsets/SwiftDevTools.swift — Swift developer toolset
import Foundation
import SwooshFiles
import SwooshTools

public struct SwiftPackageDescribeTool: SwooshTool {
    public typealias Input = SwiftPackageDescribeInput; public typealias Output = SwiftPackageDescribeOutput
    public static let name: ToolName = "swift.package_describe"; public static let displayName = "Describe Package"
    public static let description = "Parse Swift package graph"; public static let permission = SwooshPermission.swiftBuild
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.swiftDev
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let root = try await dependencies.fileAccess.resolveBookmark(id: input.rootBookmarkID)
        let result = try await dependencies.processRunner.run(executable: "/usr/bin/swift", arguments: ["package", "describe", "--type", "json"], workingDirectory: root, environment: nil)
        return try SwiftPackageDescribeOutput.parse(result.stdout)
    }
}

public struct SwiftBuildTool: SwooshTool {
    public typealias Input = SwiftBuildInput; public typealias Output = SwiftBuildOutput
    public static let name: ToolName = "swift.build"; public static let displayName = "Swift Build"
    public static let description = "Run swift build"; public static let permission = SwooshPermission.swiftBuild
    public static let risk = ToolRisk.medium; public static let approval = ApprovalPolicy.askFirstTime; public static let toolset = ToolsetID.swiftDev
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let root = try await dependencies.fileAccess.resolveBookmark(id: input.rootBookmarkID)
        let args = ["build", "-c", input.configuration.rawValue] + input.extraArguments
        let result = try await dependencies.processRunner.run(executable: "/usr/bin/swift", arguments: args, workingDirectory: root, environment: nil)
        let diagnostics = BuildDiagnosticParser().parse(result.stdout + "\n" + result.stderr)
        return SwiftBuildOutput(exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr, diagnostics: diagnostics)
    }
}

public struct SwiftTestTool: SwooshTool {
    public typealias Input = SwiftTestInput; public typealias Output = SwiftTestOutput
    public static let name: ToolName = "swift.test"; public static let displayName = "Swift Test"
    public static let description = "Run swift test"; public static let permission = SwooshPermission.swiftBuild
    public static let risk = ToolRisk.medium; public static let approval = ApprovalPolicy.askFirstTime; public static let toolset = ToolsetID.swiftDev
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let root = try await dependencies.fileAccess.resolveBookmark(id: input.rootBookmarkID)
        var args = ["test"] + input.extraArguments
        if let filter = input.filter { args.append(contentsOf: ["--filter", filter]) }
        let result = try await dependencies.processRunner.run(executable: "/usr/bin/swift", arguments: args, workingDirectory: root, environment: nil)
        let output = result.stdout + "\n" + result.stderr
        let parser = BuildDiagnosticParser()
        let summary = parser.parseTestSummary(output)
        return SwiftTestOutput(exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr, testsPassed: summary.passed, testsFailed: summary.failed, diagnostics: parser.parse(output))
    }
}

public struct SwiftFormatCheckTool: SwooshTool {
    public typealias Input = SwiftFormatCheckInput; public typealias Output = SwiftFormatCheckOutput
    public static let name: ToolName = "swift.format_check"; public static let displayName = "Format Check"
    public static let description = "Check formatting"; public static let permission = SwooshPermission.swiftBuild
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.swiftDev
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let root = try await dependencies.fileAccess.resolveBookmark(id: input.rootBookmarkID)
        let paths = input.paths ?? ["."]
        let result = try await dependencies.processRunner.run(executable: "/usr/bin/swift", arguments: ["format", "lint"] + paths, workingDirectory: root, environment: nil)
        return SwiftFormatCheckOutput(isFormatted: result.exitCode == 0, violations: parseFormatViolations(result.stdout + "\n" + result.stderr))
    }
}

public struct SwiftDiagnosticsTool: SwooshTool {
    public typealias Input = SwiftDiagnosticsInput; public typealias Output = SwiftDiagnosticsOutput
    public static let name: ToolName = "swift.diagnostics"; public static let displayName = "Diagnostics"
    public static let description = "Return diagnostics from prior build/test"; public static let permission = SwooshPermission.swiftBuild
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.swiftDev
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        SwiftDiagnosticsOutput(diagnostics: [], fromLastBuild: false)
    }
}

private struct SwiftPackageDescriptionJSON: Decodable {
    struct Product: Decodable { let name: String }
    struct Target: Decodable { let name: String; let type: String? }
    struct Dependency: Decodable { let identity: String?; let name: String?; let url: String? }
    let name: String?
    let products: [Product]?
    let targets: [Target]?
    let dependencies: [Dependency]?
}

private extension SwiftPackageDescribeOutput {
    static func parse(_ stdout: String) throws -> SwiftPackageDescribeOutput {
        let data = Data(stdout.utf8)
        let package = try JSONDecoder().decode(SwiftPackageDescriptionJSON.self, from: data)
        return SwiftPackageDescribeOutput(
            packageName: package.name,
            products: package.products?.map(\.name) ?? [],
            targets: package.targets?.map { SwiftTarget(name: $0.name, type: $0.type ?? "unknown") } ?? [],
            dependencies: package.dependencies?.map { $0.identity ?? $0.name ?? $0.url ?? "unknown" } ?? []
        )
    }
}

private func parseFormatViolations(_ output: String) -> [FormatViolation] {
    output.components(separatedBy: .newlines).compactMap { line in
        let pattern = #"^(.+?):(\d+):\d+: (.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges == 4,
              let fileRange = Range(match.range(at: 1), in: line),
              let lineRange = Range(match.range(at: 2), in: line),
              let messageRange = Range(match.range(at: 3), in: line) else {
            return nil
        }
        return FormatViolation(
            file: String(line[fileRange]),
            line: Int(line[lineRange]) ?? 1,
            description: String(line[messageRange])
        )
    }
}
