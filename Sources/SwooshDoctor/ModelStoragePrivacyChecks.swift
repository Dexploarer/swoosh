// SwooshDoctor/ModelStoragePrivacyChecks.swift — 0.9B Model + storage + privacy checks
//
// Five checks across `model`, `storage`, and `privacy` categories. Split
// from `DoctorChecks.swift` so each file stays under 400 LOC. IDs come
// from `DoctorCheckID`.

import Foundation
import SwooshTools

// ── Model ──

struct ProviderReachabilityCheck: DoctorCheck {
    let id = DoctorCheckID.providerReachability
    let title = "Provider reachability"
    let category = DoctorCategory.model

    func run(context: DoctorContext) async throws -> DoctorCheckResult {
        let endpoints = [("OpenAI", "https://api.openai.com"), ("OpenRouter", "https://openrouter.ai")]
        var reachable: [String] = [], unreachable: [String] = []

        for (name, urlStr) in endpoints {
            guard let url = URL(string: urlStr) else { continue }
            var req = URLRequest(url: url, timeoutInterval: 5)
            req.httpMethod = "HEAD"
            do {
                let (_, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, http.statusCode < 500 { reachable.append(name) }
                else { unreachable.append(name) }
            } catch { unreachable.append(name) }
        }

        if reachable.isEmpty {
            return DoctorCheckResult(checkID: id, title: title, category: category, status: .fail,
                message: "No providers reachable — check internet")
        }
        let msg = "Reachable: \(reachable.joined(separator: ", "))"
            + (unreachable.isEmpty ? "" : " · Unreachable: \(unreachable.joined(separator: ", "))")
        return DoctorCheckResult(checkID: id, title: title, category: category,
            status: unreachable.isEmpty ? .pass : .warning, message: msg)
    }
}

struct LocalModelCheck: DoctorCheck {
    let id = DoctorCheckID.localModel
    let title = "Local models"
    let category = DoctorCategory.model

    func run(context: DoctorContext) async throws -> DoctorCheckResult {
        let modelDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".swoosh/models")
        guard FileManager.default.fileExists(atPath: modelDir.path) else {
            return DoctorCheckResult(checkID: id, title: title, category: category, status: .pass,
                message: "No local models directory (optional)")
        }
        let dirs = (try? FileManager.default.contentsOfDirectory(at: modelDir, includingPropertiesForKeys: nil)) ?? []
        let models = dirs.filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("config.json").path) }
        return DoctorCheckResult(checkID: id, title: title, category: category, status: .pass,
            message: models.isEmpty ? "No local models (optional)" : "\(models.count) local model(s)")
    }
}

// ── Storage ──

struct StorageSizeCheck: DoctorCheck {
    let id = DoctorCheckID.storageSize
    let title = "Data storage size"
    let category = DoctorCategory.storage

    func run(context: DoctorContext) async throws -> DoctorCheckResult {
        let swooshDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".swoosh")
        let sizeMB = directorySize(swooshDir) / (1024 * 1024)
        if sizeMB > 1000 {
            return DoctorCheckResult(checkID: id, title: title, category: category, status: .warning,
                message: "\(sizeMB)MB — consider pruning", fixCommand: "swoosh storage prune --older-than 30d")
        }
        return DoctorCheckResult(checkID: id, title: title, category: category, status: .pass, message: "\(sizeMB)MB total")
    }

    private func directorySize(_ url: URL) -> UInt64 {
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: UInt64 = 0
        for case let file as URL in e { total += UInt64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return total
    }
}

struct CheckpointCleanupCheck: DoctorCheck {
    let id = DoctorCheckID.checkpointCleanup
    let title = "Checkpoint cleanup"
    let category = DoctorCategory.storage

    func run(context: DoctorContext) async throws -> DoctorCheckResult {
        let cpDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".swoosh/checkpoints")
        guard FileManager.default.fileExists(atPath: cpDir.path) else {
            return DoctorCheckResult(checkID: id, title: title, category: category, status: .pass, message: "No checkpoints")
        }
        let files = (try? FileManager.default.contentsOfDirectory(at: cpDir, includingPropertiesForKeys: [.creationDateKey])) ?? []
        let old = files.filter { f in
            guard let date = (try? f.resourceValues(forKeys: [.creationDateKey]).creationDate) else { return false }
            return date < Date().addingTimeInterval(-7 * 86400)
        }
        if old.count > 10 {
            return DoctorCheckResult(checkID: id, title: title, category: category, status: .warning,
                message: "\(old.count) checkpoints older than 7 days", fixCommand: "swoosh checkpoints prune --keep-last 5")
        }
        return DoctorCheckResult(checkID: id, title: title, category: category, status: .pass,
            message: "\(files.count) checkpoint(s)")
    }
}

// ── Privacy ──

struct LogPrivacyCheck: DoctorCheck {
    let id = DoctorCheckID.logPrivacy
    let title = "Log privacy"
    let category = DoctorCategory.privacy

    func run(context: DoctorContext) async throws -> DoctorCheckResult {
        let logDir = NSString(string: context.logPath).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: logDir) else {
            return DoctorCheckResult(checkID: id, title: title, category: category, status: .pass, message: "No logs directory")
        }
        let scanner = PrivacyScanner()
        let logFiles = (try? FileManager.default.contentsOfDirectory(atPath: logDir)) ?? []
        var totalIssues = 0
        for file in logFiles.prefix(20) where file.hasSuffix(".log") || file.hasSuffix(".txt") {
            let path = (logDir as NSString).appendingPathComponent(file)
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            totalIssues += scanner.scanText(String(content.prefix(50000))).issues.count
        }
        if totalIssues > 0 {
            return DoctorCheckResult(checkID: id, title: title, category: category, status: .warning,
                message: "\(totalIssues) potential secret(s) in logs", fixCommand: "swoosh logs redact")
        }
        return DoctorCheckResult(checkID: id, title: title, category: category, status: .pass,
            message: "No secrets detected in logs")
    }
}
