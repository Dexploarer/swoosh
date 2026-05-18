// SwooshDoctor/DoctorRunner.swift — Diagnostic runner + report extensions
//
// Runs all checks and produces a DoctorReport. Checks defined in DoctorChecks.swift.

import Foundation
import SwooshTools

// MARK: - Doctor runner

/// Runs all diagnostic checks and produces a DoctorReport.
public actor DoctorRunner {
    private var checks: [any DoctorCheck] = builtInChecks()

    public init() {}

    /// Run all checks and produce a report.
    public func runAll(context: DoctorContext = DoctorContext()) async -> DoctorReport {
        var results: [DoctorCheckResult] = []
        for check in checks {
            do {
                let result = try await check.run(context: context)
                results.append(result)
            } catch {
                results.append(DoctorCheckResult(
                    checkID: check.id, title: check.title, category: check.category,
                    status: .fail, message: "Check crashed: \(error.localizedDescription)"))
            }
        }
        return DoctorReport(checks: results)
    }

    /// Run checks for a specific category only.
    public func run(category: DoctorCategory, context: DoctorContext = DoctorContext()) async -> DoctorReport {
        let filtered = checks.filter { $0.category == category }
        var results: [DoctorCheckResult] = []
        for check in filtered {
            let result = try? await check.run(context: context)
            results.append(result ?? DoctorCheckResult(
                checkID: check.id, title: check.title, category: check.category,
                status: .fail, message: "Check failed"))
        }
        return DoctorReport(checks: results)
    }

    /// Register a custom check.
    public func register(_ check: any DoctorCheck) {
        checks.append(check)
    }
}

private func builtInChecks() -> [any DoctorCheck] {
    [
        SystemCheck(), DiskSpaceCheck(), SwooshDirCheck(),
        ConfigFileCheck(), ModelConfigCheck(),
        KeychainAccessCheck(), ProviderKeyCheck(),
        ProviderReachabilityCheck(), LocalModelCheck(),
        MemoryCheck(), TokenBudgetCheck(),
        StorageSizeCheck(), CheckpointCleanupCheck(),
        LogPrivacyCheck(),
    ]
}

// MARK: - Optimization recommendations

extension DoctorReport {
    /// Generate optimization recommendations based on check results.
    public var optimizationRecommendations: [String] {
        var recs: [String] = []
        let failures = checks.filter { $0.status == .fail }
        let warnings = checks.filter { $0.status == .warning }

        for f in failures {
            if let fix = f.fixCommand { recs.append("🔴 \(f.title): \(f.message ?? "") → `\(fix)`") }
            else { recs.append("🔴 \(f.title): \(f.message ?? "Fix required")") }
        }

        for w in warnings {
            if let fix = w.fixCommand { recs.append("🟡 \(w.title): \(w.message ?? "") → `\(fix)`") }
            else { recs.append("🟡 \(w.title): \(w.message ?? "")") }
        }

        if !checks.contains(where: { $0.checkID == "secrets.providers" && $0.status == .pass }) {
            recs.append("💡 Run `swoosh discover-credentials` to find API keys from other apps")
        }
        if !checks.contains(where: { $0.checkID == "config.model" && $0.status == .pass }) {
            recs.append("💡 Run `swoosh setup` to configure your default model provider")
        }
        if checks.contains(where: { $0.checkID == "perf.memory" && $0.status == .warning }) {
            recs.append("💡 Restart Swoosh to reclaim memory: `swoosh restart`")
        }

        return recs
    }

    /// Human-readable summary string.
    public var summaryText: String {
        let lines = [
            "Swoosh Doctor Report",
            "═══════════════════",
            "✅ \(summary.passed) passed  ⚠️ \(summary.warnings) warnings  ❌ \(summary.failures) failures",
            "",
        ] + checks.map { check in
            let icon: String
            switch check.status {
            case .pass: icon = "✅"
            case .warning: icon = "⚠️"
            case .fail: icon = "❌"
            case .skipped: icon = "⏭️"
            }
            return "\(icon) \(check.title): \(check.message ?? "")"
        }

        let recs = optimizationRecommendations
        if !recs.isEmpty {
            return (lines + ["", "Recommendations:", "────────────────"] + recs).joined(separator: "\n")
        }
        return lines.joined(separator: "\n")
    }
}
