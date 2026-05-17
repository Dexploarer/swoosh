// SwooshInstaller/InstallerTypes.swift — 0.9A Install/Reset/Uninstall
//
// Install layout, CLI/daemon installer, uninstaller, reset tool.
// All operations support dry-run. Never silently delete user data.

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Install layout
// ═══════════════════════════════════════════════════════════════════

public struct InstallLayout: Codable, Sendable {
    public let appPath: String
    public let configDir: String
    public let configFile: String
    public let soulFile: String
    public let stateDir: String
    public let logDir: String
    public let cacheDir: String
    public let modelDir: String
    public let mcpDir: String
    public let pluginDir: String
    public let debugBundleDir: String
    public let launchAgentDir: String
    public let launchAgentPlist: String
    public let cliBinary: String

    public static let standard = InstallLayout(
        appPath: "/Applications/Swoosh.app",
        configDir: "~/.swoosh",
        configFile: "~/.swoosh/config.yaml",
        soulFile: "~/.swoosh/SOUL.md",
        stateDir: "~/Library/Application Support/Swoosh/state",
        logDir: "~/Library/Application Support/Swoosh/logs",
        cacheDir: "~/Library/Application Support/Swoosh/caches",
        modelDir: "~/Library/Application Support/Swoosh/models",
        mcpDir: "~/Library/Application Support/Swoosh/mcp",
        pluginDir: "~/Library/Application Support/Swoosh/plugins",
        debugBundleDir: "~/Library/Application Support/Swoosh/debug-bundles",
        launchAgentDir: "~/Library/LaunchAgents",
        launchAgentPlist: "~/Library/LaunchAgents/ai.swoosh.swooshd.plist",
        cliBinary: "/usr/local/bin/swoosh"
    )

    public init(appPath: String, configDir: String, configFile: String, soulFile: String,
                stateDir: String, logDir: String, cacheDir: String, modelDir: String,
                mcpDir: String, pluginDir: String, debugBundleDir: String,
                launchAgentDir: String, launchAgentPlist: String, cliBinary: String) {
        self.appPath = appPath; self.configDir = configDir; self.configFile = configFile
        self.soulFile = soulFile; self.stateDir = stateDir; self.logDir = logDir
        self.cacheDir = cacheDir; self.modelDir = modelDir; self.mcpDir = mcpDir
        self.pluginDir = pluginDir; self.debugBundleDir = debugBundleDir
        self.launchAgentDir = launchAgentDir; self.launchAgentPlist = launchAgentPlist
        self.cliBinary = cliBinary
    }

    public var allPaths: [String] {
        [appPath, configDir, configFile, soulFile, stateDir, logDir, cacheDir,
         modelDir, mcpDir, pluginDir, debugBundleDir, launchAgentPlist, cliBinary]
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Daemon status
// ═══════════════════════════════════════════════════════════════════

public enum DaemonStatus: String, Codable, Sendable {
    case running, stopped, notInstalled, error
}

public struct DaemonState: Codable, Sendable {
    public let status: DaemonStatus
    public let pid: Int?
    public let uptime: TimeInterval?
    public let lastHealthCheck: Date?

    public init(status: DaemonStatus, pid: Int? = nil, uptime: TimeInterval? = nil,
                lastHealthCheck: Date? = nil) {
        self.status = status; self.pid = pid; self.uptime = uptime
        self.lastHealthCheck = lastHealthCheck
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Uninstall preview
// ═══════════════════════════════════════════════════════════════════

public struct UninstallPreview: Codable, Sendable {
    public let willRemove: [String]
    public let willKeepUnlessConfirmed: [String]
    public let keychainSecretsCount: Int
    public let approvedMemoryCount: Int
    public let workflowDraftCount: Int
    public let debugBundleCount: Int

    public init(willRemove: [String], willKeepUnlessConfirmed: [String],
                keychainSecretsCount: Int = 0, approvedMemoryCount: Int = 0,
                workflowDraftCount: Int = 0, debugBundleCount: Int = 0) {
        self.willRemove = willRemove; self.willKeepUnlessConfirmed = willKeepUnlessConfirmed
        self.keychainSecretsCount = keychainSecretsCount
        self.approvedMemoryCount = approvedMemoryCount
        self.workflowDraftCount = workflowDraftCount
        self.debugBundleCount = debugBundleCount
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Reset options
// ═══════════════════════════════════════════════════════════════════

public struct ResetOptions: Codable, Sendable {
    public let keepSecrets: Bool
    public let keepMemories: Bool
    public let keepWorkflows: Bool
    public let dryRun: Bool

    public static let full = ResetOptions(keepSecrets: false, keepMemories: false,
                                          keepWorkflows: false, dryRun: false)

    public static let keepAll = ResetOptions(keepSecrets: true, keepMemories: true,
                                             keepWorkflows: true, dryRun: false)

    public init(keepSecrets: Bool, keepMemories: Bool, keepWorkflows: Bool, dryRun: Bool) {
        self.keepSecrets = keepSecrets; self.keepMemories = keepMemories
        self.keepWorkflows = keepWorkflows; self.dryRun = dryRun
    }
}

public struct ResetPreview: Codable, Sendable {
    public let willReset: [String]
    public let willKeep: [String]

    public init(willReset: [String], willKeep: [String]) {
        self.willReset = willReset; self.willKeep = willKeep
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - LaunchAgent plist
// ═══════════════════════════════════════════════════════════════════

public struct LaunchAgentGenerator: Sendable {
    public init() {}

    public func generatePlist(binaryPath: String = "/usr/local/bin/swoosh") -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>ai.swoosh.swooshd</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(binaryPath)</string>
                <string>daemon</string>
                <string>run</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>StandardOutPath</key>
            <string>~/Library/Application Support/Swoosh/logs/swooshd.out.log</string>
            <key>StandardErrorPath</key>
            <string>~/Library/Application Support/Swoosh/logs/swooshd.err.log</string>
        </dict>
        </plist>
        """
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Installer audit
// ═══════════════════════════════════════════════════════════════════

public struct InstallerAuditEvent: Codable, Sendable {
    public let kind: InstallerAuditKind
    public let message: String
    public let createdAt: Date

    public init(kind: InstallerAuditKind, message: String, createdAt: Date = Date()) {
        self.kind = kind; self.message = message; self.createdAt = createdAt
    }
}

public enum InstallerAuditKind: String, Codable, Sendable {
    case cliInstalled, launchAgentInstalled
    case daemonStarted, daemonStopped, daemonRestarted
    case resetPreviewed, resetApplied
    case uninstallPreviewed, uninstallApplied
}
