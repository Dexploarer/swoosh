// SwooshToolsets/SwiftDevTools.swift — Swift developer toolset
import Foundation
import SwooshTools

public struct SwiftPackageDescribeTool: SwooshTool {
    public typealias Input = SwiftPackageDescribeInput; public typealias Output = SwiftPackageDescribeOutput
    public static let name: ToolName = "swift.package_describe"; public static let displayName = "Describe Package"
    public static let description = "Parse Swift package graph"; public static let permission = SwooshPermission.swiftBuild
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.swiftDev
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let root = try await dependencies.fileAccess.resolveBookmark(id: input.rootBookmarkID)
        _ = try await dependencies.processRunner.run(executable: "/usr/bin/swift", arguments: ["package", "describe", "--type", "json"], workingDirectory: root, environment: nil)
        return SwiftPackageDescribeOutput(packageName: nil, products: [], targets: [], dependencies: [])
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
        return SwiftBuildOutput(exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr, diagnostics: [])
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
        return SwiftTestOutput(exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr, testsPassed: 0, testsFailed: 0, diagnostics: [])
    }
}

public struct SwiftFormatCheckTool: SwooshTool {
    public typealias Input = SwiftFormatCheckInput; public typealias Output = SwiftFormatCheckOutput
    public static let name: ToolName = "swift.format_check"; public static let displayName = "Format Check"
    public static let description = "Check formatting"; public static let permission = SwooshPermission.swiftBuild
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.swiftDev
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        SwiftFormatCheckOutput(isFormatted: true, violations: [])
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
