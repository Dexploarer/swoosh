// SwooshConfig/PermissionProfile.swift — Permission-first setup
//
// "Before the first tool call: configure what the agent is allowed to do."
// Permissions should be visible at onboarding, not discovered only when a dangerous command appears.

import Foundation
import SwooshTools

// MARK: - Permission profile

public enum PermissionProfilePreset: String, Codable, Sendable, CaseIterable {
    /// No shell writes, no file writes, no app automation.
    case safe

    /// File read/write in approved folders, shell with approval, Git, Xcode.
    case developer

    /// Calendar, Reminders, Mail drafts, Shortcuts, scheduled workflows.
    case automation

    /// Shell, browser, file writes, MCP, workflow scheduling. High-risk still requires approval.
    case power

    /// Mainnet trading with explicit human prompts for write/sign/broadcast actions.
    case trader

    /// Full unattended operation. The model can use every permission and approval gate can be disabled.
    case autonomous

    /// Fully custom.
    case custom
}

/// Granular permission settings for each resource category.
public struct PermissionProfile: Codable, Sendable {
    public var preset: PermissionProfilePreset
    public var files: FilePermissions
    public var shell: ShellPermissions
    public var apps: AppPermissions
    public var network: NetworkPermissions
    public var memory: MemoryPermissions

    public init(
        preset: PermissionProfilePreset = .developer,
        files: FilePermissions = .developer,
        shell: ShellPermissions = .developer,
        apps: AppPermissions = .default,
        network: NetworkPermissions = .default,
        memory: MemoryPermissions = .default
    ) {
        self.preset = preset
        self.files = files
        self.shell = shell
        self.apps = apps
        self.network = network
        self.memory = memory
    }

    /// Generate from preset
    public static func from(preset: PermissionProfilePreset) -> PermissionProfile {
        switch preset {
        case .safe:
            return PermissionProfile(
                preset: .safe,
                files: FilePermissions(desktopAccess: .deny, documentsAccess: .deny, selectedRepos: .ask, downloads: .deny),
                shell: ShellPermissions(readOnly: .deny, packageInstall: .deny, destructive: .deny, sudo: .deny),
                apps: .init(calendar: .deny, reminders: .deny, mail: .deny, messages: .deny),
                network: .init(providerAPIs: .allow, arbitraryFetch: .deny),
                memory: .init(saveFacts: .ask, sensitiveFacts: .deny, autoSave: false)
            )
        case .developer:
            return PermissionProfile(
                preset: .developer,
                files: .developer,
                shell: .developer,
                apps: .default,
                network: .default,
                memory: .default
            )
        case .automation:
            return PermissionProfile(
                preset: .automation,
                files: FilePermissions(desktopAccess: .ask, documentsAccess: .ask, selectedRepos: .allow, downloads: .ask),
                shell: ShellPermissions(readOnly: .allow, packageInstall: .ask, destructive: .deny, sudo: .deny),
                apps: .init(calendar: .allow, reminders: .allow, mail: .ask, messages: .deny),
                network: .default,
                memory: .init(saveFacts: .allow, sensitiveFacts: .ask, autoSave: true)
            )
        case .power:
            return PermissionProfile(
                preset: .power,
                files: FilePermissions(desktopAccess: .allow, documentsAccess: .allow, selectedRepos: .allow, downloads: .allow),
                shell: ShellPermissions(readOnly: .allow, packageInstall: .ask, destructive: .ask, sudo: .deny),
                apps: .init(calendar: .allow, reminders: .allow, mail: .ask, messages: .ask),
                network: .init(providerAPIs: .allow, arbitraryFetch: .allow),
                memory: .init(saveFacts: .allow, sensitiveFacts: .ask, autoSave: true)
            )
        case .trader:
            return PermissionProfile(
                preset: .trader,
                files: FilePermissions(desktopAccess: .ask, documentsAccess: .ask, selectedRepos: .allow, downloads: .ask),
                shell: ShellPermissions(readOnly: .allow, packageInstall: .ask, destructive: .ask, sudo: .deny),
                apps: .default,
                network: .init(providerAPIs: .allow, arbitraryFetch: .allow),
                memory: .default
            )
        case .autonomous:
            return PermissionProfile(
                preset: .autonomous,
                files: FilePermissions(desktopAccess: .allow, documentsAccess: .allow, selectedRepos: .allow, downloads: .allow),
                shell: ShellPermissions(readOnly: .allow, packageInstall: .allow, destructive: .allow, sudo: .allow),
                apps: .init(calendar: .allow, reminders: .allow, mail: .allow, messages: .allow),
                network: .init(providerAPIs: .allow, arbitraryFetch: .allow),
                memory: .init(saveFacts: .allow, sensitiveFacts: .allow, autoSave: true)
            )
        case .custom:
            return .init(preset: .custom)
        }
    }
}

extension PermissionProfilePreset {
    public var defaultToolPolicy: ToolCallPolicy {
        switch self {
        case .safe:
            return .restrictive
        case .developer, .automation:
            return .defaultAgent
        case .power:
            return ToolCallPolicy(
                maxToolCallsPerTurn: 16,
                maxToolChainDepth: 12,
                allowModelToolCalls: true,
                allowHumanOnlyFromModel: false,
                allowCriticalToolsFromModel: true,
                requireApprovalForMediumRiskAndAbove: true
            )
        case .trader:
            return ToolCallPolicy(
                maxToolCallsPerTurn: 16,
                maxToolChainDepth: 12,
                allowModelToolCalls: true,
                allowHumanOnlyFromModel: true,
                allowCriticalToolsFromModel: true,
                requireApprovalForMediumRiskAndAbove: true
            )
        case .autonomous:
            return .autonomous
        case .custom:
            return .defaultAgent
        }
    }

    public var defaultSafetyConfig: SwooshSafetyConfig {
        switch self {
        case .autonomous:
            return .autonomous
        case .trader:
            return .trader
        case .power:
            return .development
        case .safe, .developer, .automation, .custom:
            return .defaultAgent
        }
    }

    public var grantedSwooshPermissions: Set<SwooshPermission> {
        PermissionProfile.from(preset: self).grantedSwooshPermissions
    }
}

extension PermissionProfile {
    public var grantedSwooshPermissions: Set<SwooshPermission> {
        switch preset {
        case .safe:
            return [
                .deviceProfileRead, .toolRead, .memoryRead, .auditRead,
                .networkAccess, .networkRead
            ]
        case .developer:
            return [
                .deviceProfileRead, .installedAppsRead, .runningAppsRead,
                .selectedFolderRead, .selectedFolderWrite, .fileRead, .fileWrite,
                .shellRead, .shellRun, .toolRead, .toolWrite, .memoryRead, .memoryWrite,
                .auditRead, .auditWrite, .gitRead, .gitWrite, .swiftBuild, .xcodeBuild,
                .webSearch, .webExtract, .networkAccess, .networkRead,
                .workflowRead, .workflowWrite, .workflowRun,
                .skillsRead, .skillsWrite, .goalsRead, .goalsWrite,
                .manifestRead, .manifestRun
            ]
        case .automation:
            return PermissionProfile.from(preset: .developer).grantedSwooshPermissions.union([
                .calendarRead, .calendarWrite, .remindersRead, .remindersWrite,
                .shortcutsRun, .scheduleRead, .scheduleWrite, .scheduleRun,
                .appUsageRead, .focusModeRead
            ])
        case .power:
            return Set(SwooshPermission.allCases).subtracting([
                .evmMainnetWrite,
                .solanaMainnetWrite
            ])
        case .trader:
            return PermissionProfile.from(preset: .developer).grantedSwooshPermissions.union([
                .evmRead,
                .evmBuildTransaction,
                .evmRequestSignature,
                .evmBroadcast,
                .evmMainnetWrite,
                .solanaRead,
                .solanaBuildTransaction,
                .solanaRequestSignature,
                .solanaBroadcast,
                .solanaMainnetWrite,
                .networkRead,
                .hyperliquidTrade,
                .hyperliquidTransfer,
            ])
        case .autonomous:
            return Set(SwooshPermission.allCases)
        case .custom:
            return PermissionProfile.from(preset: .developer).grantedSwooshPermissions
        }
    }
}

// MARK: - Permission level

public enum PermissionLevel: String, Codable, Sendable {
    case allow  // Always allowed
    case ask    // Ask every time
    case deny   // Always denied
}

// MARK: - Category-specific permissions

public struct FilePermissions: Codable, Sendable {
    public var desktopAccess: PermissionLevel
    public var documentsAccess: PermissionLevel
    public var selectedRepos: PermissionLevel
    public var downloads: PermissionLevel

    public init(
        desktopAccess: PermissionLevel = .ask,
        documentsAccess: PermissionLevel = .ask,
        selectedRepos: PermissionLevel = .allow,
        downloads: PermissionLevel = .ask
    ) {
        self.desktopAccess = desktopAccess
        self.documentsAccess = documentsAccess
        self.selectedRepos = selectedRepos
        self.downloads = downloads
    }

    public static let developer = FilePermissions(
        desktopAccess: .ask,
        documentsAccess: .ask,
        selectedRepos: .allow,
        downloads: .ask
    )
}

public struct ShellPermissions: Codable, Sendable {
    public var readOnly: PermissionLevel
    public var packageInstall: PermissionLevel
    public var destructive: PermissionLevel
    public var sudo: PermissionLevel

    public init(
        readOnly: PermissionLevel = .allow,
        packageInstall: PermissionLevel = .ask,
        destructive: PermissionLevel = .ask,
        sudo: PermissionLevel = .deny
    ) {
        self.readOnly = readOnly
        self.packageInstall = packageInstall
        self.destructive = destructive
        self.sudo = sudo
    }

    public static let developer = ShellPermissions(
        readOnly: .allow,
        packageInstall: .ask,
        destructive: .ask,
        sudo: .deny
    )
}

public struct AppPermissions: Codable, Sendable {
    public var calendar: PermissionLevel
    public var reminders: PermissionLevel
    public var mail: PermissionLevel
    public var messages: PermissionLevel

    public init(
        calendar: PermissionLevel = .deny,
        reminders: PermissionLevel = .deny,
        mail: PermissionLevel = .deny,
        messages: PermissionLevel = .deny
    ) {
        self.calendar = calendar
        self.reminders = reminders
        self.mail = mail
        self.messages = messages
    }

    public static let `default` = AppPermissions()
}

public struct NetworkPermissions: Codable, Sendable {
    public var providerAPIs: PermissionLevel
    public var arbitraryFetch: PermissionLevel

    public init(
        providerAPIs: PermissionLevel = .allow,
        arbitraryFetch: PermissionLevel = .ask
    ) {
        self.providerAPIs = providerAPIs
        self.arbitraryFetch = arbitraryFetch
    }

    public static let `default` = NetworkPermissions()
}

public struct MemoryPermissions: Codable, Sendable {
    public var saveFacts: PermissionLevel
    public var sensitiveFacts: PermissionLevel
    public var autoSave: Bool

    public init(
        saveFacts: PermissionLevel = .ask,
        sensitiveFacts: PermissionLevel = .deny,
        autoSave: Bool = false
    ) {
        self.saveFacts = saveFacts
        self.sensitiveFacts = sensitiveFacts
        self.autoSave = autoSave
    }

    public static let `default` = MemoryPermissions()
}
