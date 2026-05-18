// SwooshTools/SwiftDevToolTypes.swift — Swift developer tool input/output types
import Foundation

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
