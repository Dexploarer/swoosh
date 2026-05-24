// SwooshConfig/SwooshRuntimeConfig.swift — 0.9S Persisted runtime config
//
// The Codable record written to `~/.swoosh/config.json` by `swoosh
// setup` and read by every shell at startup. Pairs a permission
// profile preset with the concrete tool-call policy and safety flags
// it expands to (via `PermissionProfilePreset.defaultToolPolicy` and
// `defaultSafetyConfig`). The decoder is generous with missing fields
// so configs persisted by older setup runs keep loading.

import Foundation
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
