// Tests/SwooshConfigTests/PermissionProfileTests.swift
//
// Pin every `PermissionProfilePreset` to its expected:
//   • category-level `PermissionProfile.from(preset:)` output (file,
//     shell, app, network, memory)
//   • `defaultToolPolicy` / `defaultSafetyConfig` shape
//   • `grantedSwooshPermissions` set (firewall grant list)
// These maps are the user-facing contract — accidental drift would
// silently expand or restrict what the agent can do at a given preset.

import Testing
import Foundation
@testable import SwooshConfig
@testable import SwooshTools

@Suite("PermissionProfile.from(preset:)")
struct PermissionProfileFactoryTests {

    @Test("safe denies file + shell + apps; allows provider APIs only")
    func safePreset() {
        let p = PermissionProfile.from(preset: .safe)
        #expect(p.files.desktopAccess == .deny)
        #expect(p.shell.sudo == .deny)
        #expect(p.apps.calendar == .deny)
        #expect(p.network.providerAPIs == .allow)
        #expect(p.network.arbitraryFetch == .deny)
        #expect(p.memory.autoSave == false)
    }

    @Test("autonomous allows everything including sudo")
    func autonomousPreset() {
        let p = PermissionProfile.from(preset: .autonomous)
        #expect(p.shell.sudo == .allow)
        #expect(p.shell.destructive == .allow)
        #expect(p.network.arbitraryFetch == .allow)
        #expect(p.memory.autoSave == true)
    }

    @Test("every preset round-trips its preset id")
    func presetIdRoundTrip() {
        for preset in PermissionProfilePreset.allCases {
            #expect(PermissionProfile.from(preset: preset).preset == preset)
        }
    }
}

@Suite("PermissionProfilePreset runtime defaults")
struct PermissionProfileDefaultsTests {

    @Test("safe uses the low-chain restrictive policy")
    func safeToolPolicy() {
        // `restrictive` allows model tool calls but caps chain depth at 1
        // and requires approval for medium+ — the audit-friendly baseline.
        let policy = PermissionProfilePreset.safe.defaultToolPolicy
        #expect(policy.maxToolChainDepth == 1)
        #expect(policy.allowCriticalToolsFromModel == false)
        #expect(policy.requireApprovalForMediumRiskAndAbove == true)
    }

    @Test("autonomous uses autonomous tool policy + safety config")
    func autonomousDefaults() {
        let policy = PermissionProfilePreset.autonomous.defaultToolPolicy
        #expect(policy.allowHumanOnlyFromModel == true)
        #expect(policy.allowCriticalToolsFromModel == true)
        // Autonomous safety config bypasses approval prompts.
        let safety = PermissionProfilePreset.autonomous.defaultSafetyConfig
        #expect(safety.modelSelfApprovalEnabled == true)
    }

    @Test("trader requires approvals even with human-only enabled")
    func traderRequiresApproval() {
        let policy = PermissionProfilePreset.trader.defaultToolPolicy
        #expect(policy.allowHumanOnlyFromModel == true)
        #expect(policy.requireApprovalForMediumRiskAndAbove == true)
    }
}

@Suite("PermissionProfile.grantedSwooshPermissions")
struct GrantedPermissionsTests {

    @Test("safe grants only the read-only baseline")
    func safeGrants() {
        let grants = PermissionProfile.from(preset: .safe).grantedSwooshPermissions
        #expect(grants.contains(.memoryRead))
        #expect(grants.contains(.auditRead))
        #expect(grants.contains(.networkAccess))
        #expect(!grants.contains(.fileWrite))
        #expect(!grants.contains(.shellRun))
        #expect(!grants.contains(.evmMainnetWrite))
    }

    @Test("developer grants dev + image but no chain writes")
    func developerGrants() {
        let grants = PermissionProfile.from(preset: .developer).grantedSwooshPermissions
        #expect(grants.contains(.fileWrite))
        #expect(grants.contains(.shellRun))
        #expect(grants.contains(.imageGenerate))
        #expect(!grants.contains(.videoGenerate))
        #expect(!grants.contains(.evmMainnetWrite))
    }

    @Test("automation extends developer with calendar + video/3D")
    func automationGrants() {
        let dev = PermissionProfile.from(preset: .developer).grantedSwooshPermissions
        let automation = PermissionProfile.from(preset: .automation).grantedSwooshPermissions
        #expect(automation.isSuperset(of: dev))
        #expect(automation.contains(.calendarWrite))
        #expect(automation.contains(.videoGenerate))
        #expect(automation.contains(.threeDGenerate))
        #expect(!automation.contains(.evmMainnetWrite))
    }

    @Test("trader grants chain reads/writes + hyperliquid")
    func traderGrants() {
        let grants = PermissionProfile.from(preset: .trader).grantedSwooshPermissions
        #expect(grants.contains(.evmMainnetWrite))
        #expect(grants.contains(.solanaMainnetWrite))
        #expect(grants.contains(.hyperliquidTrade))
        #expect(grants.contains(.hyperliquidTransfer))
    }

    @Test("power grants everything except mainnet writes")
    func powerGrants() {
        let grants = PermissionProfile.from(preset: .power).grantedSwooshPermissions
        #expect(!grants.contains(.evmMainnetWrite))
        #expect(!grants.contains(.solanaMainnetWrite))
        #expect(grants.contains(.shellRun))
        #expect(grants.contains(.fileWrite))
    }

    @Test("autonomous grants every SwooshPermission case")
    func autonomousGrants() {
        let grants = PermissionProfile.from(preset: .autonomous).grantedSwooshPermissions
        #expect(grants == Set(SwooshPermission.allCases))
    }

    @Test("custom falls back to developer defaults")
    func customGrants() {
        let custom = PermissionProfile.from(preset: .custom).grantedSwooshPermissions
        let dev = PermissionProfile.from(preset: .developer).grantedSwooshPermissions
        #expect(custom == dev)
    }
}
