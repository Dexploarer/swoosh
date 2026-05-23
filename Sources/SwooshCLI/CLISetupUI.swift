// SwooshCLI/CLISetupUI.swift — TTY conformance to SwooshScout's SetupUI — 0.4A
//
// Lives in its own file (was previously bottom-of-ScoutMemoryCommands)
// because it's mechanically unrelated to scout / memory and shrinks
// that command file below the 400-LOC ceiling.

import Foundation
import SwooshConfig

struct CLISetupUI: SetupUI {
    func showProgress(_ step: SetupStepID, message: String) async { print("  ⟳ \(message)") }

    func showResult(_ step: SetupStepID, result: SetupResult) async {
        switch result {
        case .success(let s): print("  ✓ \(s)")
        case .skipped(let r): print("  ○ Skipped: \(r)")
        case .failed(let e):  print("  ✗ Failed: \(e)")
        }
    }

    func showVerification(_ step: SetupStepID, result: VerificationResult) async {
        switch result {
        case .passed(let d): print("  ✓ Verified: \(d)")
        case .warning(let m): print("  ⚠ \(m)")
        case .failed(let e):  print("  ✗ Verification failed: \(e)")
        }
    }

    func askYesNo(_ prompt: String, default defaultVal: Bool) async -> Bool {
        let suffix = defaultVal ? "[Y/n]" : "[y/N]"
        print("  \(prompt) \(suffix) ", terminator: "")
        guard let input = readLine()?.lowercased() else { return defaultVal }
        return input.isEmpty ? defaultVal : (input == "y" || input == "yes")
    }

    func askChoice(_ prompt: String, options: [String], default defaultIdx: Int) async -> Int {
        print("  \(prompt) [\(defaultIdx + 1)]: ", terminator: "")
        guard let input = readLine(), let idx = Int(input) else { return defaultIdx }
        return max(0, min(idx - 1, options.count - 1))
    }

    func askString(_ prompt: String, default defaultVal: String?) async -> String {
        let suffix = defaultVal.map { " [\($0)]" } ?? ""
        print("  \(prompt)\(suffix): ", terminator: "")
        guard let input = readLine(), !input.isEmpty else { return defaultVal ?? "" }
        return input
    }

    func askSecret(_ prompt: String) async -> String {
        print("  \(prompt): ", terminator: "")
        return readLine() ?? ""
    }

    func showReport(_ report: SetupReport) async {
        print("\n─── Setup Report ──────────────────────────────")
        for step in report.steps {
            let icon: String
            switch step.verification {
            case .passed: icon = "✓"
            case .warning: icon = "○"
            case .failed: icon = "✗"
            }
            print("  \(icon) \(step.stepID.rawValue)")
        }
        print()
    }
}
