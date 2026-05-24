// SwooshConfig/PermissionProfile.swift — 0.9S Permission-first setup
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
