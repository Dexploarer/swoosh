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
        var passed = 0, failed = 0, skipped = 0

        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            // Swift Testing: "✔ Test run with 26 tests in 6 suites passed after 0.003 seconds."
            if line.contains("Test run with") && line.contains("passed") {
                if let match = line.range(of: #"(\d+) tests?"#, options: .regularExpression) {
                    passed = Int(line[match].filter(\.isNumber)) ?? 0
                }
            }
            // XCTest: "Executed 10 tests, with 2 failures (1 unexpected) in 0.5 (0.5) seconds"
            if line.contains("Executed") && line.contains("tests") {
                let parts = line.components(separatedBy: " ")
                for (i, part) in parts.enumerated() {
                    if part == "tests," || part == "test,", i > 0 {
                        let total = Int(parts[i-1]) ?? 0
                        passed = total
                    }
                    if part == "failures" || part.hasPrefix("failure"), i > 0 {
                        failed = Int(parts[i-1]) ?? 0
                        passed = max(0, passed - failed)
                    }
                }
            }
            // "Test … passed" / "Test … failed"
            if line.hasPrefix("✔ Test \"") { passed += 1 }
            if line.hasPrefix("✘ Test \"") { failed += 1 }
        }

        return (passed, failed, skipped)
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
