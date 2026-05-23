// SwooshCLI/DoctorCLICommand.swift — 0.9B Doctor subcommand
//
// `swoosh doctor` and its three flags:
//   --fix / --scaffold   Create any missing ~/.swoosh state directories.
//                        Despite the legacy `--fix` name, this is the
//                        only in-process repair; every other check's
//                        `fixCommand` is surfaced as a suggestion.
//   --print-fixes        Emit suggested fix commands as a runnable
//                        shell script on stdout. Pipe through review,
//                        then `sh` to actually execute.
//   --json               Single-line JSON summary instead of formatted
//                        output. Used by tooling that wraps `doctor`.
//
// Extracted from SwooshCommand.swift to keep both files under the 400-LOC
// ceiling and to give the doctor flow a single-responsibility home.

import ArgumentParser
import Foundation
import SwooshConfig
import SwooshDoctor

struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "doctor", abstract: "Run comprehensive diagnostics.")

    @Flag(name: [.customLong("fix"), .customLong("scaffold")],
          help: "Create any missing Swoosh state directories under ~/.swoosh/.")
    var scaffold = false

    @Flag(name: .long, help: "Print fixCommand strings for non-passing checks as a shell script.")
    var printFixes = false

    @Flag(name: .long, help: "Output as JSON.")
    var json = false

    @Option(name: .customLong("config-dir"), help: "State directory to inspect instead of ~/.swoosh.")
    var configDirectory: String?

    func run() async throws {
        let config = makeSwooshConfigStore(configDirectory: configDirectory)
        if scaffold {
            try config.ensureDirectories()
        }
        let runner = DoctorRunner()
        let result = await runner.runAll(context: DoctorContext(
            configPath: config.configFile.path,
            statePath: config.configDirectory.path,
            logPath: config.logsDir.path
        ))

        if json {
            print("{\"passed\": \(result.isHealthy), \"checks\": \(result.checks.count), \"failures\": \(result.summary.failures)}")
            return
        }

        if printFixes {
            print("#!/bin/sh")
            print("# Swoosh Doctor — fix commands for \(result.summary.failures) failure(s), \(result.summary.warnings) warning(s).")
            print("# Review before piping to a shell. Some commands ('swoosh setup') are interactive.")
            for check in result.checks {
                guard check.status != .pass, check.status != .skipped, let fix = check.fixCommand else { continue }
                print("# \(check.title): \(check.message ?? "")")
                print(fix)
            }
            return
        }

        print("Swoosh Doctor\n")

        var currentCategory = ""
        for check in result.checks {
            if check.category.rawValue != currentCategory {
                currentCategory = check.category.rawValue
                print("─── \(currentCategory) ───")
            }

            let icon: String
            let detail: String
            switch check.status {
            case .pass:    icon = "✓"; detail = check.message ?? "passed"
            case .warning: icon = "○"; detail = check.message ?? "warning"
            case .fail:    icon = "✗"; detail = check.message ?? "failed"
            case .skipped: icon = "-"; detail = check.message ?? "skipped"
            }

            print("  \(icon) \(check.title): \(detail)")
            // Surface the fixCommand for warnings + failures, not just
            // failures — a "○" item with a suggested next step is just
            // as actionable.
            if let f = check.fixCommand, check.status == .warning || check.status == .fail {
                print("    Fix: \(f)")
            }
        }

        print()
        if result.summary.failures == 0, result.summary.warnings == 0 {
            print("All checks passed. ✓")
        } else if result.summary.failures == 0 {
            print("\(result.summary.warnings) warning(s) found.")
        } else {
            print("\(result.summary.failures) issue(s) found.")
            print("Run `swoosh doctor --print-fixes` to dump suggested commands as a shell script.")
            if !scaffold {
                print("Run `swoosh doctor --scaffold` to create any missing state directories.")
            }
        }
    }
}
