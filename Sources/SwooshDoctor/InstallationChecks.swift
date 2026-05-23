// SwooshDoctor/InstallationChecks.swift — 0.9B Platform, disk, dir, memory
//
// Five checks in the `installation` + `daemon` categories. Split from
// `DoctorChecks.swift` to keep every source file under the 400-LOC
// ceiling. Identifiers come from `DoctorCheckID` so renames here are
// caught by the compiler in `DoctorReport.optimizationRecommendations`.

import Foundation
import SwooshClient
import SwooshConfig
import SwooshTools

// ── Installation ──

struct SystemCheck: DoctorCheck {
    let id = DoctorCheckID.platform
    let title = "Platform"
    let category = DoctorCategory.installation

    func run(context: DoctorContext) async throws -> DoctorCheckResult {
        let info = ProcessInfo.processInfo
        let os = info.operatingSystemVersionString
        let ram = info.physicalMemory / (1024 * 1024 * 1024)
        let cpus = info.activeProcessorCount
        #if arch(arm64)
        let arch = "arm64 (Apple Silicon)"
        #else
        let arch = "x86_64"
        #endif
        return DoctorCheckResult(
            checkID: id, title: title, category: category, status: .pass,
            message: "\(arch) · macOS \(os) · \(ram)GB RAM · \(cpus) cores")
    }
}

struct DiskSpaceCheck: DoctorCheck {
    let id = DoctorCheckID.disk
    let title = "Disk space"
    let category = DoctorCategory.installation

    func run(context: DoctorContext) async throws -> DoctorCheckResult {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let values = try home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let freeGB = (values.volumeAvailableCapacityForImportantUsage ?? 0) / (1024 * 1024 * 1024)
        if freeGB < 2 {
            return DoctorCheckResult(checkID: id, title: title, category: category, status: .fail,
                message: "\(freeGB)GB free — need at least 2GB", fixCommand: "df -h ~")
        } else if freeGB < 10 {
            return DoctorCheckResult(checkID: id, title: title, category: category, status: .warning,
                message: "\(freeGB)GB free — consider freeing space for local models")
        }
        return DoctorCheckResult(checkID: id, title: title, category: category, status: .pass,
            message: "\(freeGB)GB available")
    }
}

struct SwooshDirCheck: DoctorCheck {
    let id = DoctorCheckID.swooshDirectory
    let title = "Swoosh directory"
    let category = DoctorCategory.installation

    func run(context: DoctorContext) async throws -> DoctorCheckResult {
        let swooshDir = URL(
            fileURLWithPath: NSString(string: context.statePath).expandingTildeInPath,
            isDirectory: true
        )
        let fm = FileManager.default
        let dirs = [
            "memories",
            "skills",
            "workflows",
            "goals",
            "manifesting",
            "scout",
            "cron",
            "logs",
            "artifacts",
            "mcp",
            "workers",
            "setup-reports",
            "models",
            "checkpoints",
        ]
        var missing: [String] = []
        for d in dirs {
            if !fm.fileExists(atPath: swooshDir.appendingPathComponent(d).path) { missing.append(d) }
        }
        if missing.isEmpty {
            return DoctorCheckResult(checkID: id, title: title, category: category, status: .pass,
                message: "All directories present")
        }
        return DoctorCheckResult(checkID: id, title: title, category: category,
            status: missing.count > 3 ? .fail : .warning,
            message: "Missing: \(missing.joined(separator: ", "))",
            fixCommand: "mkdir -p ~/.swoosh/{\(dirs.joined(separator: ","))}")
    }
}

struct MemoryCheck: DoctorCheck {
    let id = DoctorCheckID.memory
    let title = "Memory pressure"
    let category = DoctorCategory.installation

    func run(context: DoctorContext) async throws -> DoctorCheckResult {
        let total = ProcessInfo.processInfo.physicalMemory
        let totalGB = total / (1024 * 1024 * 1024)

        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rawPtr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rawPtr, &count)
            }
        }

        if result == KERN_SUCCESS {
            let usedMB = info.resident_size / (1024 * 1024)
            if usedMB > 500 {
                return DoctorCheckResult(checkID: id, title: title, category: category, status: .warning,
                    message: "Swoosh using \(usedMB)MB of \(totalGB)GB — consider restarting")
            }
            return DoctorCheckResult(checkID: id, title: title, category: category, status: .pass,
                message: "\(usedMB)MB used · \(totalGB)GB total")
        }
        return DoctorCheckResult(checkID: id, title: title, category: category, status: .pass,
            message: "\(totalGB)GB total RAM")
    }
}

// ── Daemon ──

struct RuntimeReadinessCheck: DoctorCheck {
    let id = DoctorCheckID.runtimeReadiness
    let title = "Runtime readiness"
    let category = DoctorCategory.daemon

    func run(context: DoctorContext) async throws -> DoctorCheckResult {
        let config = SwooshConfigStore(configDirectory: stateURL(context))
        let report = await readinessReport(config: config)
        return DoctorCheckResult(
            checkID: id,
            title: title,
            category: category,
            status: doctorStatus(report.state),
            message: report.summary,
            fixCommand: report.components.first { $0.status == .blocked || $0.status == .warning }?.fixCommand
        )
    }

    private func readinessReport(config: SwooshConfigStore) async -> SwooshReadinessReport {
        guard let client = client(config: config) else {
            return SwooshReadinessDetector(config: config).report(inputs: SwooshReadinessInputs(daemonReachable: false))
        }
        guard await client.health() else {
            return SwooshReadinessDetector(config: config).report(inputs: SwooshReadinessInputs(daemonReachable: false))
        }
        do {
            return try await client.readiness()
        } catch {
            return SwooshReadinessDetector(config: config).report(inputs: SwooshReadinessInputs(daemonReachable: true))
        }
    }

    private func client(config: SwooshConfigStore) -> SwooshAPIClient? {
        let runtime = try? config.load(SwooshRuntimeConfig.self)
        let host = runtime?.daemonHost ?? "127.0.0.1"
        let port = runtime?.daemonPort ?? 8787
        guard let url = URL(string: "http://\(host):\(port)") else { return nil }
        let token = (try? String(contentsOf: config.apiTokenFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return SwooshAPIClient(baseURL: url, token: token)
    }

    private func stateURL(_ context: DoctorContext) -> URL {
        URL(
            fileURLWithPath: NSString(string: context.statePath).expandingTildeInPath,
            isDirectory: true
        )
    }

    private func doctorStatus(_ state: SwooshReadinessState) -> DoctorCheckStatus {
        switch state {
        case .ready:
            return .pass
        case .degraded:
            return .warning
        case .blocked:
            return .fail
        }
    }
}
