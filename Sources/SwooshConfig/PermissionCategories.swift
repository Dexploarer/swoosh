// SwooshConfig/PermissionCategories.swift — 0.9S Category-specific permission shapes
//
// PermissionLevel + the five category structs (file, shell, app, network,
// memory) that compose a `PermissionProfile`. Lives in its own file so
// `PermissionProfile.swift` stays focused on the preset factory and
// `PermissionProfile+SwooshDefaults.swift` stays focused on the runtime
// policy mapping.

import Foundation

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
