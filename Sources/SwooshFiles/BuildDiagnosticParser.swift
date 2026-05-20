// SwooshFiles/BuildDiagnosticParser.swift — Build diagnostic extraction (0.4C)
//
// Parses Swift/Clang compiler diagnostics from stderr.

import Foundation
import SwooshTools

public struct BuildDiagnosticParser: Sendable {
    public init() {}

    /// Parse diagnostics from compiler output (combined stdout+stderr).
    public func parse(_ output: String) -> [BuildDiagnostic] {
        var diagnostics: [BuildDiagnostic] = []
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            if let diagnostic = parseLine(line) {
                diagnostics.append(diagnostic)
            }
        }

        return diagnostics
    }

    /// Parse a Swift test summary from output.
    public func parseTestSummary(_ output: String) -> (passed: Int, failed: Int, skipped: Int) {
        var summaryTotal: Int?
        var summaryFailures = 0
        var individualPassed = 0
        var individualFailed = 0
        let skipped = 0

        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("Test run with") && line.contains("passed") {
                if let match = line.range(of: #"(\d+) tests?"#, options: .regularExpression) {
                    summaryTotal = Int(line[match].filter(\.isNumber))
                }
            }
            if line.contains("Executed") && line.contains("tests") {
                let parts = line.components(separatedBy: " ")
                for (i, part) in parts.enumerated() {
                    if part == "tests," || part == "test,", i > 0 {
                        summaryTotal = Int(parts[i-1]) ?? summaryTotal
                    }
                    if part == "failures" || part.hasPrefix("failure"), i > 0 {
                        summaryFailures = Int(parts[i-1]) ?? summaryFailures
                    }
                }
            }
            if line.hasPrefix("✔ Test \"") { individualPassed += 1 }
            if line.hasPrefix("✘ Test \"") { individualFailed += 1 }
        }

        if let summaryTotal {
            let failures = max(summaryFailures, individualFailed)
            return (max(0, summaryTotal - failures), failures, skipped)
        }
        return (individualPassed, individualFailed, skipped)
    }

    // MARK: - Line parsing

    private func parseLine(_ line: String) -> BuildDiagnostic? {
        // Format: /path/to/File.swift:42:17: error: message
        //         /path/to/File.swift:42:17: warning: message
        //         /path/to/File.swift:42:17: note: message

        let pattern = #"^(.+?):(\d+):(\d+): (error|warning|note): (.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges == 6 else {
            return nil
        }

        func extract(_ range: Int) -> String? {
            guard let r = Range(match.range(at: range), in: line) else { return nil }
            return String(line[r])
        }

        let file = extract(1)
        let lineNum = extract(2).flatMap(Int.init)
        let col = extract(3).flatMap(Int.init)
        let severityStr = extract(4) ?? "unknown"
        let message = extract(5) ?? line

        let severity: DiagnosticSeverity
        switch severityStr {
        case "error":   severity = .error
        case "warning": severity = .warning
        case "note":    severity = .note
        default:        severity = .error
        }

        return BuildDiagnostic(
            severity: severity,
            message: message,
            file: file,
            line: lineNum,
            column: col
        )
    }
}
