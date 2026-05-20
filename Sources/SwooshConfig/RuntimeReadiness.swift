// SwooshConfig/RuntimeReadiness.swift — Shared runtime readiness model (0.9P)

import Foundation
import SwooshClient
import SwooshTools

public struct SwooshRuntimeConfig: Codable, Sendable, Equatable {
    public let version: Int
    public let setupMode: String
    public let permissionProfile: String
    public let modelPath: String
    public let daemonHost: String
    public let daemonPort: Int
    public let preferredProviderID: String?
    public let localDiagnosticFallback: Bool
    public let toolPolicy: ToolCallPolicy
    public let safetyConfig: SwooshSafetyConfig
    public let configuredAt: String

    public init(
        version: Int = 1,
        setupMode: String,
        permissionProfile: String,
        modelPath: String,
        daemonHost: String = "127.0.0.1",
        daemonPort: Int = 8787,
        preferredProviderID: String?,
        localDiagnosticFallback: Bool = true,
        toolPolicy: ToolCallPolicy? = nil,
        safetyConfig: SwooshSafetyConfig? = nil,
        configuredAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        let preset = PermissionProfilePreset(rawValue: permissionProfile) ?? .developer
        self.version = version
        self.setupMode = setupMode
        self.permissionProfile = permissionProfile
        self.modelPath = modelPath
        self.daemonHost = daemonHost
        self.daemonPort = daemonPort
        self.preferredProviderID = preferredProviderID
        self.localDiagnosticFallback = localDiagnosticFallback
        self.toolPolicy = toolPolicy ?? preset.defaultToolPolicy
        self.safetyConfig = safetyConfig ?? preset.defaultSafetyConfig
        self.configuredAt = configuredAt
    }

    public init(
        version: Int = 1,
        setupMode: String,
        permissionProfile: String,
        modelPath: String,
        daemonHost: String = "127.0.0.1",
        daemonPort: Int = 8787,
        localDiagnosticFallback: Bool = true,
        toolPolicy: ToolCallPolicy? = nil,
        safetyConfig: SwooshSafetyConfig? = nil,
        configuredAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.init(
            version: version,
            setupMode: setupMode,
            permissionProfile: permissionProfile,
            modelPath: modelPath,
            daemonHost: daemonHost,
            daemonPort: daemonPort,
            preferredProviderID: nil,
            localDiagnosticFallback: localDiagnosticFallback,
            toolPolicy: toolPolicy,
            safetyConfig: safetyConfig,
            configuredAt: configuredAt
        )
    }

    private enum CodingKeys: String, CodingKey {
        case version, setupMode, permissionProfile, modelPath, daemonHost, daemonPort
        case preferredProviderID, localDiagnosticFallback, toolPolicy, safetyConfig, configuredAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let permissionProfile = try c.decode(String.self, forKey: .permissionProfile)
        let preset = PermissionProfilePreset(rawValue: permissionProfile) ?? .developer
        self.version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        self.setupMode = try c.decode(String.self, forKey: .setupMode)
        self.permissionProfile = permissionProfile
        self.modelPath = try c.decode(String.self, forKey: .modelPath)
        self.daemonHost = try c.decodeIfPresent(String.self, forKey: .daemonHost) ?? "127.0.0.1"
        self.daemonPort = try c.decodeIfPresent(Int.self, forKey: .daemonPort) ?? 8787
        self.preferredProviderID = try c.decodeIfPresent(String.self, forKey: .preferredProviderID)
        self.localDiagnosticFallback = try c.decodeIfPresent(Bool.self, forKey: .localDiagnosticFallback) ?? true
        self.toolPolicy = try c.decodeIfPresent(ToolCallPolicy.self, forKey: .toolPolicy) ?? preset.defaultToolPolicy
        self.safetyConfig = try c.decodeIfPresent(SwooshSafetyConfig.self, forKey: .safetyConfig) ?? preset.defaultSafetyConfig
        self.configuredAt = try c.decodeIfPresent(String.self, forKey: .configuredAt) ?? ISO8601DateFormatter().string(from: Date())
    }
}

public struct SwooshReadinessInputs: Sendable {
    public let daemonReachable: Bool?
    public let chatEnabled: Bool?
    public let activeProviderName: String?
    public let activeModel: String?
    public let promptableSkillCount: Int?

    public init(
        daemonReachable: Bool? = nil,
        chatEnabled: Bool? = nil,
        activeProviderName: String? = nil,
        activeModel: String? = nil,
        promptableSkillCount: Int? = nil
    ) {
        self.daemonReachable = daemonReachable
        self.chatEnabled = chatEnabled
        self.activeProviderName = activeProviderName
        self.activeModel = activeModel
        self.promptableSkillCount = promptableSkillCount
    }
}

public struct SwooshReadinessDetector: Sendable {
    public let config: SwooshConfigStore

    public init(config: SwooshConfigStore = SwooshConfigStore()) {
        self.config = config
    }

    public func report(inputs: SwooshReadinessInputs = SwooshReadinessInputs()) -> SwooshReadinessReport {
        let components = [
            directoriesComponent(),
            configComponent(),
            tokenComponent(),
            daemonComponent(inputs: inputs),
            modelComponent(inputs: inputs),
            skillsComponent(inputs: inputs),
        ]
        let state = state(for: components)
        return SwooshReadinessReport(
            state: state,
            summary: summary(for: state, components: components),
            components: components
        )
    }

    public func loadRuntimeConfig() -> SwooshRuntimeConfig? {
        try? config.load(SwooshRuntimeConfig.self)
    }

    private func directoriesComponent() -> SwooshReadinessComponent {
        let missing = config.requiredStateDirectories.filter {
            !FileManager.default.fileExists(atPath: $0.path)
        }
        guard missing.isEmpty else {
            return SwooshReadinessComponent(
                id: "state.directories",
                title: "State directories",
                status: .blocked,
                detail: "Missing \(missing.map(\.lastPathComponent).joined(separator: ", "))",
                fixCommand: "swoosh setup quick"
            )
        }
        return SwooshReadinessComponent(
            id: "state.directories",
            title: "State directories",
            status: .ready,
            detail: "\(config.requiredStateDirectories.count) directories ready"
        )
    }

    private func configComponent() -> SwooshReadinessComponent {
        guard FileManager.default.fileExists(atPath: config.configFile.path) else {
            return SwooshReadinessComponent(
                id: "config.file",
                title: "Runtime config",
                status: .blocked,
                detail: "No config at \(config.configFile.path)",
                fixCommand: "swoosh setup quick"
            )
        }
        guard let runtime = loadRuntimeConfig() else {
            return SwooshReadinessComponent(
                id: "config.file",
                title: "Runtime config",
                status: .blocked,
                detail: "Config exists but is not a Swoosh runtime config",
                fixCommand: "swoosh setup quick"
            )
        }
        return SwooshReadinessComponent(
            id: "config.file",
            title: "Runtime config",
            status: .ready,
            detail: "\(runtime.setupMode) · \(runtime.permissionProfile) · \(runtime.modelPath)"
        )
    }

    private func tokenComponent() -> SwooshReadinessComponent {
        let token = (try? String(contentsOf: config.apiTokenFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token, !token.isEmpty else {
            return SwooshReadinessComponent(
                id: "auth.api_token",
                title: "API token",
                status: .blocked,
                detail: "No bearer token at \(config.apiTokenFile.path)",
                fixCommand: "swoosh setup quick"
            )
        }
        return SwooshReadinessComponent(
            id: "auth.api_token",
            title: "API token",
            status: .ready,
            detail: "Bearer token present"
        )
    }

    private func daemonComponent(inputs: SwooshReadinessInputs) -> SwooshReadinessComponent {
        switch (inputs.daemonReachable, inputs.chatEnabled) {
        case (.some(true), .some(true)):
            return SwooshReadinessComponent(
                id: "daemon.chat",
                title: "Daemon chat",
                status: .ready,
                detail: "swooshd is reachable and chat is enabled"
            )
        case (.some(true), .some(false)):
            return SwooshReadinessComponent(
                id: "daemon.chat",
                title: "Daemon chat",
                status: .blocked,
                detail: "swooshd is reachable but no agent kernel is configured",
                fixCommand: "swift run swooshd"
            )
        case (.some(true), .none):
            return SwooshReadinessComponent(
                id: "daemon.chat",
                title: "Daemon chat",
                status: .warning,
                detail: "swooshd is reachable; chat status was not checked"
            )
        case (.some(false), _):
            return SwooshReadinessComponent(
                id: "daemon.chat",
                title: "Daemon chat",
                status: .warning,
                detail: "swooshd is not reachable",
                fixCommand: "swift run swooshd"
            )
        case (.none, _):
            return SwooshReadinessComponent(
                id: "daemon.chat",
                title: "Daemon chat",
                status: .warning,
                detail: "Daemon reachability not checked",
                fixCommand: "swift run swooshd"
            )
        }
    }

    private func modelComponent(inputs: SwooshReadinessInputs) -> SwooshReadinessComponent {
        if let activeProviderName = inputs.activeProviderName, let activeModel = inputs.activeModel {
            return SwooshReadinessComponent(
                id: "model.provider",
                title: "Model provider",
                status: .ready,
                detail: "\(activeProviderName) · \(activeModel)"
            )
        }
        let runtime = loadRuntimeConfig()
        let modelPath = runtime?.modelPath ?? ""
        let fallback = runtime?.localDiagnosticFallback ?? false
        if fallback || modelPath == "hybrid" {
            return SwooshReadinessComponent(
                id: "model.provider",
                title: "Model provider",
                status: .ready,
                detail: "Local diagnostic fallback is available"
            )
        }
        if modelPath == "local", isAppleSilicon {
            return SwooshReadinessComponent(
                id: "model.provider",
                title: "Model provider",
                status: .ready,
                detail: "Local MLX path configured on Apple Silicon"
            )
        }
        return SwooshReadinessComponent(
            id: "model.provider",
            title: "Model provider",
            status: .blocked,
            detail: "No runnable model provider or fallback configured",
            fixCommand: "swoosh setup quick"
        )
    }

    private func skillsComponent(inputs: SwooshReadinessInputs) -> SwooshReadinessComponent {
        guard let count = inputs.promptableSkillCount else {
            return SwooshReadinessComponent(
                id: "skills.promptable",
                title: "Promptable skills",
                status: .warning,
                detail: "Skill catalog not checked"
            )
        }
        return SwooshReadinessComponent(
            id: "skills.promptable",
            title: "Promptable skills",
            status: count == 0 ? .warning : .ready,
            detail: "\(count) reviewed or promoted skill(s)"
        )
    }

    private var isAppleSilicon: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }

    private func state(for components: [SwooshReadinessComponent]) -> SwooshReadinessState {
        if components.contains(where: { $0.status == .blocked }) { return .blocked }
        if components.contains(where: { $0.status == .warning }) { return .degraded }
        return .ready
    }

    private func summary(
        for state: SwooshReadinessState,
        components: [SwooshReadinessComponent]
    ) -> String {
        switch state {
        case .ready:
            return "Ready: setup, daemon chat, and model path are available."
        case .degraded:
            let warnings = components.filter { $0.status == .warning }.map(\.title)
            return "Degraded: \(warnings.joined(separator: ", "))."
        case .blocked:
            let blocked = components.filter { $0.status == .blocked }.map(\.title)
            return "Blocked: \(blocked.joined(separator: ", "))."
        }
    }
}
