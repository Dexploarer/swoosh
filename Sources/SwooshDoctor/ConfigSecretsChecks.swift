// SwooshDoctor/ConfigSecretsChecks.swift — 0.9B Config + secrets diagnostics
//
// Five checks across the `config` and `secrets` categories. Split from
// `DoctorChecks.swift` so each file stays under 400 LOC. IDs come from
// `DoctorCheckID`.

import Foundation
import SwooshConfig
import SwooshTools

// ── Config ──

struct ConfigFileCheck: DoctorCheck {
    let id = DoctorCheckID.configFile
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
    let id = DoctorCheckID.modelConfig
    let title = "Default model"
    let category = DoctorCategory.config

    func run(context: DoctorContext) async throws -> DoctorCheckResult {
        let configPath = NSString(string: context.configPath).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: configPath),
              let content = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return DoctorCheckResult(checkID: id, title: title, category: category, status: .warning,
                message: "No config — no default model set", fixCommand: "swoosh setup")
        }
        if (try? JSONDecoder().decode(SwooshRuntimeConfig.self, from: Data(content.utf8))) != nil
            || content.contains("model:")
            || content.contains("provider:")
            || content.contains("\"modelPath\"")
        {
            return DoctorCheckResult(checkID: id, title: title, category: category, status: .pass,
                message: "Model configured")
        }
        return DoctorCheckResult(checkID: id, title: title, category: category, status: .warning,
            message: "No default model configured", fixCommand: "swoosh setup")
    }
}

struct TokenBudgetCheck: DoctorCheck {
    let id = DoctorCheckID.tokenBudget
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
        if let runtime = try? JSONDecoder().decode(SwooshRuntimeConfig.self, from: Data(content.utf8)),
           runtime.localDiagnosticFallback {
            return DoctorCheckResult(checkID: id, title: title, category: category, status: .pass,
                message: "Local diagnostic provider has no remote token spend")
        }
        return DoctorCheckResult(checkID: id, title: title, category: category, status: .warning,
            message: "No budget limits set", fixCommand: "swoosh config set budget.daily_limit 25")
    }
}

// ── Secrets ──

struct KeychainAccessCheck: DoctorCheck {
    let id = DoctorCheckID.keychainAccess
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
            return DoctorCheckResult(checkID: id, title: title, category: category, status: .pass,
                message: "Keychain reachable; no cloud credentials required")
        }
        return DoctorCheckResult(checkID: id, title: title, category: category, status: .fail,
            message: "Keychain access denied (status: \(status))")
    }
}

struct ProviderKeyCheck: DoctorCheck {
    let id = DoctorCheckID.providerKeys
    let title = "Provider API keys"
    let category = DoctorCategory.secrets

    func run(context: DoctorContext) async throws -> DoctorCheckResult {
        let keys = ["OPENAI_API_KEY", "OPENROUTER_API_KEY", "ELIZA_CLOUD_API_KEY"]
        let found = keys.filter { ProcessInfo.processInfo.environment[$0] != nil }
        if found.isEmpty {
            let configPath = NSString(string: context.configPath).expandingTildeInPath
            if let content = try? String(contentsOfFile: configPath, encoding: .utf8),
               let runtime = try? JSONDecoder().decode(SwooshRuntimeConfig.self, from: Data(content.utf8)),
               runtime.localDiagnosticFallback {
                return DoctorCheckResult(checkID: id, title: title, category: category, status: .pass,
                    message: "Local diagnostic provider active; remote keys optional")
            }
            return DoctorCheckResult(checkID: id, title: title, category: category, status: .warning,
                message: "No provider keys in environment", fixCommand: "swoosh discover-credentials")
        }
        return DoctorCheckResult(checkID: id, title: title, category: category, status: .pass,
            message: "\(found.count) key(s): \(found.joined(separator: ", "))")
    }
}
