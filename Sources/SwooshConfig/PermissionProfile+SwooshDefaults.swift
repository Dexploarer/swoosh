// SwooshConfig/PermissionProfile+SwooshDefaults.swift — 0.9S Runtime defaults per preset
//
// Maps each `PermissionProfilePreset` to its concrete `ToolCallPolicy`,
// `SwooshSafetyConfig`, and granted `SwooshPermission` set. The
// `PermissionProfile.swift` factory composes the high-level category
// values; this file maps presets to the firewall/policy primitives the
// runtime actually enforces.

import Foundation
import SwooshTools

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
        case .safe:           return Self.safePermissions
        case .developer:      return Self.developerPermissions
        case .automation:     return Self.automationPermissions
        case .power:          return Self.powerPermissions
        case .trader:         return Self.traderPermissions
        case .autonomous:     return Self.autonomousPermissions
        case .custom:         return Self.developerPermissions
        }
    }

    // MARK: - Preset grant sets

    private static let safePermissions: Set<SwooshPermission> = [
        .deviceProfileRead, .toolRead, .memoryRead, .auditRead,
        .networkAccess, .networkRead,
    ]

    private static let developerPermissions: Set<SwooshPermission> = [
        .deviceProfileRead, .installedAppsRead, .runningAppsRead,
        .selectedFolderRead, .selectedFolderWrite, .fileRead, .fileWrite,
        .shellRead, .shellRun, .toolRead, .toolWrite, .memoryRead, .memoryWrite,
        .auditRead, .auditWrite, .gitRead, .gitWrite, .swiftBuild, .xcodeBuild,
        .webSearch, .webExtract, .networkAccess, .networkRead,
        .workflowRead, .workflowWrite, .workflowRun,
        .skillsRead, .skillsWrite, .goalsRead, .goalsWrite,
        .manifestRead, .manifestRun,
        .imageGenerate,
    ]

    private static let automationPermissions: Set<SwooshPermission> = developerPermissions.union([
        .calendarRead, .calendarWrite, .remindersRead, .remindersWrite,
        .shortcutsRun, .scheduleRead, .scheduleWrite, .scheduleRun,
        .appUsageRead, .focusModeRead,
        .videoGenerate, .threeDGenerate,
    ])

    private static let powerPermissions: Set<SwooshPermission> = Set(SwooshPermission.allCases).subtracting([
        .evmMainnetWrite,
        .solanaMainnetWrite,
    ])

    private static let traderPermissions: Set<SwooshPermission> = developerPermissions.union([
        .evmRead, .evmBuildTransaction, .evmRequestSignature, .evmBroadcast, .evmMainnetWrite,
        .solanaRead, .solanaBuildTransaction, .solanaRequestSignature, .solanaBroadcast, .solanaMainnetWrite,
        .networkRead, .hyperliquidTrade, .hyperliquidTransfer,
    ])

    private static let autonomousPermissions: Set<SwooshPermission> = Set(SwooshPermission.allCases)
}
