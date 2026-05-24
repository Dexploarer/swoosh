// Tests/SwooshConfigTests/RuntimeReadinessTests.swift
//
// Pin `SwooshRuntimeConfig` encoder/decoder + the per-preset default
// expansion (toolPolicy + safetyConfig). The custom `init(from:)` is
// generous with missing fields so configs persisted by older `swoosh
// setup` runs keep loading — this suite locks that behavior in.

import Testing
import Foundation
@testable import SwooshConfig
@testable import SwooshTools

@Suite("SwooshRuntimeConfig defaults")
struct SwooshRuntimeConfigDefaultsTests {

    @Test("defaults expand from preset when no policy/safety supplied")
    func presetDefaults() {
        let config = SwooshRuntimeConfig(
            setupMode: "quick",
            permissionProfile: "autonomous",
            modelPath: "/tmp/model",
            preferredProviderID: nil
        )
        #expect(config.toolPolicy.allowHumanOnlyFromModel == true)
        #expect(config.safetyConfig.modelSelfApprovalEnabled == true)
    }

    @Test("unknown preset falls back to developer defaults")
    func unknownPresetFallsBack() {
        let config = SwooshRuntimeConfig(
            setupMode: "quick",
            permissionProfile: "not-a-real-preset",
            modelPath: "/tmp/model",
            preferredProviderID: nil
        )
        #expect(config.toolPolicy.allowModelToolCalls == true)
        #expect(config.toolPolicy.allowHumanOnlyFromModel == false)
    }

    @Test("explicit toolPolicy and safetyConfig are preserved verbatim")
    func explicitPolicyPreserved() {
        let explicit = ToolCallPolicy(
            maxToolCallsPerTurn: 99,
            maxToolChainDepth: 7,
            allowModelToolCalls: false,
            allowHumanOnlyFromModel: false,
            allowCriticalToolsFromModel: false,
            requireApprovalForMediumRiskAndAbove: false
        )
        let config = SwooshRuntimeConfig(
            setupMode: "full",
            permissionProfile: "safe",
            modelPath: "/x",
            preferredProviderID: "openai",
            toolPolicy: explicit
        )
        #expect(config.toolPolicy.maxToolCallsPerTurn == 99)
        #expect(config.toolPolicy.maxToolChainDepth == 7)
    }
}

@Suite("SwooshRuntimeConfig Codable")
struct SwooshRuntimeConfigCodableTests {

    private func roundTrip(_ original: SwooshRuntimeConfig) throws -> SwooshRuntimeConfig {
        let data = try JSONEncoder().encode(original)
        return try JSONDecoder().decode(SwooshRuntimeConfig.self, from: data)
    }

    @Test("full round-trip preserves every field")
    func fullRoundTrip() throws {
        let original = SwooshRuntimeConfig(
            setupMode: "quick",
            permissionProfile: "developer",
            modelPath: "/path/to/model",
            daemonHost: "10.0.0.5",
            daemonPort: 9090,
            preferredProviderID: "openrouter",
            localDiagnosticFallback: false
        )
        let decoded = try roundTrip(original)
        #expect(decoded.setupMode == "quick")
        #expect(decoded.permissionProfile == "developer")
        #expect(decoded.modelPath == "/path/to/model")
        #expect(decoded.daemonHost == "10.0.0.5")
        #expect(decoded.daemonPort == 9090)
        #expect(decoded.preferredProviderID == "openrouter")
        #expect(decoded.localDiagnosticFallback == false)
    }

    @Test("legacy config without daemonHost/Port defaults to loopback:8787")
    func legacyDecoderDefaults() throws {
        let json = #"""
        {
            "setupMode": "quick",
            "permissionProfile": "developer",
            "modelPath": "/m"
        }
        """#
        let data = try #require(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(SwooshRuntimeConfig.self, from: data)
        #expect(decoded.daemonHost == "127.0.0.1")
        #expect(decoded.daemonPort == 8787)
        #expect(decoded.localDiagnosticFallback == true)
        #expect(decoded.version == 1)
    }

    @Test("legacy config without toolPolicy fills from preset")
    func legacyToolPolicyFromPreset() throws {
        let json = #"""
        {"setupMode":"quick","permissionProfile":"safe","modelPath":"/m"}
        """#
        let data = try #require(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(SwooshRuntimeConfig.self, from: data)
        // safe preset → restrictive policy: caps chain depth at 1.
        #expect(decoded.toolPolicy.maxToolChainDepth == 1)
        #expect(decoded.toolPolicy.requireApprovalForMediumRiskAndAbove == true)
    }
}
