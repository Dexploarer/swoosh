// SwooshDoctor/DoctorChecks.swift — Built-in diagnostic checks
//
// Each check: id, title, category, run() → DoctorCheckResult with fix command.

import Foundation
import SwooshTools

// ── Installation ──

struct SystemCheck: DoctorCheck {
    let id = "sys.platform"
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
    let id = "sys.disk"
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
    let id = "sys.swoosh_dir"
    let title = "Swoosh directory"
    let category = DoctorCategory.installation

    func run(context: DoctorContext) async throws -> DoctorCheckResult {
        let swooshDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".swoosh")
        let fm = FileManager.default
        let dirs = ["config", "state", "logs", "skills", "checkpoints", "models"]
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
    let id = "perf.memory"
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

// ── Config ──

struct ConfigFileCheck: DoctorCheck {
    let id = "config.file"
    let title = "Config file"
    let category = DoctorCategory.config

    func run(context: DoctorContext) async throws -> DoctorCheckResult {
        let path = NSString(string: context.configPath).expandingTildeInPath
        if FileManager.default.fileExists(atPath: path) {
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
            return DoctorCheckResult(checkID: id, title: title, category: category, status: .pass,
                message: "Found (\(size) bytes)")
        }
        return DoctorCheckResult(checkID: id, title: title, category: category, status: .warning,
            message: "No config file — using defaults", fixCommand: "swoosh setup")
    }
}

struct ModelConfigCheck: DoctorCheck {
    let id = "config.model"
    let title = "Default model"
    let category = DoctorCategory.config

    func run(context: DoctorContext) async throws -> DoctorCheckResult {
        let configPath = NSString(string: context.configPath).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: configPath),
              let content = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return DoctorCheckResult(checkID: id, title: title, category: category, status: .warning,
                message: "No config — no default model set", fixCommand: "swoosh setup")
        }
        if content.contains("model:") || content.contains("provider:") {
            return DoctorCheckResult(checkID: id, title: title, category: category, status: .pass,
                message: "Model configured")
        }
        return DoctorCheckResult(checkID: id, title: title, category: category, status: .warning,
            message: "No default model configured", fixCommand: "swoosh setup")
    }
}

struct TokenBudgetCheck: DoctorCheck {
    let id = "perf.budget"
    let title = "Token budget"
    let category = DoctorCategory.config

    func run(context: DoctorContext) async throws -> DoctorCheckResult {
        let configPath = NSString(string: context.configPath).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: configPath),
              let content = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return DoctorCheckResult(checkID: id, title: title, category: category, status: .warning,
                message: "No budget configured — using defaults ($25/day limit)",
                fixCommand: "swoosh config set budget.daily_limit 25")
        }
        if content.contains("budget") || content.contains("cost_limit") {
            return DoctorCheckResult(checkID: id, title: title, category: category, status: .pass,
                message: "Budget policy configured")
        }
        return DoctorCheckResult(checkID: id, title: title, category: category, status: .warning,
            message: "No budget limits set", fixCommand: "swoosh config set budget.daily_limit 25")
    }
}

// ── Secrets ──

struct KeychainAccessCheck: DoctorCheck {
    let id = "secrets.keychain"
    let title = "Keychain access"
    let category = DoctorCategory.secrets

    func run(context: DoctorContext) async throws -> DoctorCheckResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "ai.swoosh.secrets",
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let items = result as? [[String: Any]] {
            return DoctorCheckResult(checkID: id, title: title, category: category, status: .pass,
                message: "\(items.count) credential(s) in Keychain")
        } else if status == errSecItemNotFound {
            return DoctorCheckResult(checkID: id, title: title, category: category, status: .warning,
                message: "No credentials stored", fixCommand: "swoosh discover-credentials")
        }
        return DoctorCheckResult(checkID: id, title: title, category: category, status: .fail,
            message: "Keychain access denied (status: \(status))")
    }
}

struct ProviderKeyCheck: DoctorCheck {
    let id = "secrets.providers"
    let title = "Provider API keys"
    let category = DoctorCategory.secrets

    func run(context: DoctorContext) async throws -> DoctorCheckResult {
        let keys = ["OPENAI_API_KEY", "ANTHROPIC_API_KEY", "OPENROUTER_API_KEY",
                     "GEMINI_API_KEY", "DEEPSEEK_API_KEY", "GROQ_API_KEY"]
        let found = keys.filter { ProcessInfo.processInfo.environment[$0] != nil }
        if found.isEmpty {
            return DoctorCheckResult(checkID: id, title: title, category: category, status: .warning,
                message: "No provider keys in environment", fixCommand: "swoosh discover-credentials")
        }
        return DoctorCheckResult(checkID: id, title: title, category: category, status: .pass,
            message: "\(found.count) key(s): \(found.joined(separator: ", "))")
    }
}

// ── Model ──

struct ProviderReachabilityCheck: DoctorCheck {
    let id = "model.reachability"
    let title = "Provider reachability"
    let category = DoctorCategory.model

    func run(context: DoctorContext) async throws -> DoctorCheckResult {
        let endpoints = [("OpenAI", "https://api.openai.com"), ("Anthropic", "https://api.anthropic.com"), ("OpenRouter", "https://openrouter.ai")]
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
    let id = "model.local"
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
    let id = "storage.size"
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
    let id = "storage.checkpoints"
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
    let id = "privacy.logs"
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
