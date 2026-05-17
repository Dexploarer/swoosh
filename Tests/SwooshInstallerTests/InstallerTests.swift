// Tests/SwooshInstallerTests/InstallerTests.swift — 0.9A

import Testing
import Foundation
@testable import SwooshInstaller
@testable import SwooshTools

// ═══════════════════════════════════════════════════════════════
// MARK: - Install Layout Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Install Layout")
struct InstallLayoutTests {

    @Test("Standard layout paths")
    func standardPaths() {
        let layout = InstallLayout.standard
        #expect(layout.appPath == "/Applications/Swoosh.app")
        #expect(layout.configFile == "~/.swoosh/config.yaml")
        #expect(layout.soulFile == "~/.swoosh/SOUL.md")
        #expect(layout.cliBinary == "/usr/local/bin/swoosh")
    }

    @Test("LaunchAgent plist path")
    func launchAgentPath() {
        let layout = InstallLayout.standard
        #expect(layout.launchAgentPlist == "~/Library/LaunchAgents/ai.swoosh.swooshd.plist")
    }

    @Test("All paths listed")
    func allPathsListed() {
        let layout = InstallLayout.standard
        #expect(layout.allPaths.count >= 10)
    }

    @Test("State and logs in Application Support")
    func stateInAppSupport() {
        let layout = InstallLayout.standard
        #expect(layout.stateDir.contains("Application Support/Swoosh"))
        #expect(layout.logDir.contains("Application Support/Swoosh"))
    }

    @Test("Debug bundles in Application Support")
    func debugBundlesPath() {
        let layout = InstallLayout.standard
        #expect(layout.debugBundleDir.contains("Application Support/Swoosh"))
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Daemon Status Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Daemon Status")
struct DaemonStatusTests {

    @Test("Running daemon")
    func runningDaemon() {
        let state = DaemonState(status: .running, pid: 12345, uptime: 3600)
        #expect(state.status == .running)
        #expect(state.pid == 12345)
    }

    @Test("Stopped daemon")
    func stoppedDaemon() {
        let state = DaemonState(status: .stopped)
        #expect(state.status == .stopped)
        #expect(state.pid == nil)
    }

    @Test("Not installed daemon")
    func notInstalledDaemon() {
        let state = DaemonState(status: .notInstalled)
        #expect(state.status == .notInstalled)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Uninstall Preview Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Uninstall Preview")
struct UninstallPreviewTests {

    @Test("Preview lists what will be removed")
    func listsRemovable() {
        let preview = UninstallPreview(
            willRemove: ["CLI helper", "LaunchAgent", "logs"],
            willKeepUnlessConfirmed: ["Keychain secrets", "approved memories"],
            keychainSecretsCount: 3,
            approvedMemoryCount: 12
        )
        #expect(preview.willRemove.count == 3)
        #expect(preview.willKeepUnlessConfirmed.count == 2)
    }

    @Test("Preview shows user data counts")
    func showsUserDataCounts() {
        let preview = UninstallPreview(
            willRemove: [], willKeepUnlessConfirmed: [],
            keychainSecretsCount: 5, approvedMemoryCount: 20,
            workflowDraftCount: 3, debugBundleCount: 1
        )
        #expect(preview.keychainSecretsCount == 5)
        #expect(preview.approvedMemoryCount == 20)
        #expect(preview.workflowDraftCount == 3)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Reset Options Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Reset Options")
struct ResetOptionsTests {

    @Test("Full reset removes everything")
    func fullReset() {
        let opts = ResetOptions.full
        #expect(!opts.keepSecrets)
        #expect(!opts.keepMemories)
        #expect(!opts.keepWorkflows)
    }

    @Test("Keep-all preserves everything")
    func keepAll() {
        let opts = ResetOptions.keepAll
        #expect(opts.keepSecrets)
        #expect(opts.keepMemories)
        #expect(opts.keepWorkflows)
    }

    @Test("Selective keep-secrets")
    func keepSecrets() {
        let opts = ResetOptions(keepSecrets: true, keepMemories: false,
                                keepWorkflows: false, dryRun: false)
        #expect(opts.keepSecrets)
        #expect(!opts.keepMemories)
    }

    @Test("Dry-run flag")
    func dryRun() {
        let opts = ResetOptions(keepSecrets: false, keepMemories: false,
                                keepWorkflows: false, dryRun: true)
        #expect(opts.dryRun)
    }

    @Test("Reset preview")
    func resetPreview() {
        let preview = ResetPreview(
            willReset: ["state", "logs", "caches"],
            willKeep: ["Keychain secrets", "approved memories"]
        )
        #expect(preview.willReset.count == 3)
        #expect(preview.willKeep.count == 2)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - LaunchAgent Tests
// ═══════════════════════════════════════════════════════════════

@Suite("LaunchAgent")
struct LaunchAgentTests {

    @Test("Plist generated")
    func plistGenerated() {
        let gen = LaunchAgentGenerator()
        let plist = gen.generatePlist()
        #expect(plist.contains("ai.swoosh.swooshd"))
        #expect(plist.contains("RunAtLoad"))
        #expect(plist.contains("KeepAlive"))
    }

    @Test("Plist uses correct binary path")
    func plistBinaryPath() {
        let gen = LaunchAgentGenerator()
        let plist = gen.generatePlist(binaryPath: "/opt/swoosh/bin/swoosh")
        #expect(plist.contains("/opt/swoosh/bin/swoosh"))
    }

    @Test("Plist has log paths")
    func plistLogPaths() {
        let gen = LaunchAgentGenerator()
        let plist = gen.generatePlist()
        #expect(plist.contains("swooshd.out.log"))
        #expect(plist.contains("swooshd.err.log"))
    }

    @Test("Plist does not contain secrets")
    func plistNoSecrets() {
        let gen = LaunchAgentGenerator()
        let plist = gen.generatePlist()
        #expect(!plist.contains("api_key"))
        #expect(!plist.contains("token"))
        #expect(!plist.contains("Bearer"))
        #expect(!plist.contains("sk_"))
    }
}
