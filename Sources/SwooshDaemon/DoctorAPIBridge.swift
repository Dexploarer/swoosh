// SwooshDaemon/DoctorAPIBridge.swift — 0.5A Doctor runner ↔ HTTP API
//
// Runs the daemon-side `DoctorRunner` and translates the resulting
// `DoctorReport` (SwooshDoctor) into a `DoctorReportResponse` (SwooshClient
// wire types). One static method per role so the closure passed into
// `SwooshAPIRuntimeSources.doctorReport` stays a single line.
//
// The Doctor inspects on-disk state (`~/.swoosh`), so the bridge accepts
// the daemon's resolved swoosh state directory as a `DoctorContext`. The
// daemon constructs that context from its `SwooshConfigStore` at startup,
// same way every other bridge does.

import Foundation
import SwooshAPI
import SwooshClient
import SwooshConfig
import SwooshDoctor

extension SwooshDaemon {

    static func doctorContext(config: SwooshConfigStore) -> DoctorContext {
        DoctorContext(
            configPath: config.configFile.path,
            statePath: config.configDirectory.path,
            logPath: config.logsDir.path
        )
    }

    static func doctorReportResponse(config: SwooshConfigStore) async -> DoctorReportResponse {
        let runner = DoctorRunner()
        let report = await runner.runAll(context: doctorContext(config: config))
        return DoctorReportResponse(
            id: report.id,
            createdAt: report.createdAt,
            checks: report.checks.map { check in
                DoctorCheckSummary(
                    id: check.checkID,
                    title: check.title,
                    category: check.category.rawValue,
                    status: check.status.rawValue,
                    message: check.message,
                    fixCommand: check.fixCommand
                )
            },
            summary: DoctorSummaryWire(
                passed: report.summary.passed,
                warnings: report.summary.warnings,
                failures: report.summary.failures,
                skipped: report.summary.skipped
            ),
            recommendations: report.optimizationRecommendations,
            isHealthy: report.isHealthy
        )
    }
}
