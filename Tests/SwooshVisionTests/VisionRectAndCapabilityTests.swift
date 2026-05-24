// Tests/SwooshVisionTests/VisionRectAndCapabilityTests.swift — 0.9S
//
// Pure-logic tests for the value types and capability matrix that
// drive any future picker UI + the `CGRect → VisionRect` bridge.

import Foundation
import Testing
@testable import SwooshVision

@Suite("VisionRect bridge from CGRect")
struct VisionRectBridgeTests {

    @Test("Bridges origin + size from CGRect verbatim")
    func basicBridge() {
        #if canImport(Vision)
        let rect = VisionRect(rect: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
        #expect(rect.x == 0.1)
        #expect(rect.y == 0.2)
        #expect(rect.width == 0.3)
        #expect(rect.height == 0.4)
        #endif
    }

    @Test("Round-trips through Codable")
    func codableRoundTrip() throws {
        let rect = VisionRect(x: 0.0, y: 0.5, width: 1.0, height: 0.25)
        let data = try JSONEncoder().encode(rect)
        let decoded = try JSONDecoder().decode(VisionRect.self, from: data)
        #expect(decoded == rect)
    }
}

@Suite("VisionCapability — display names + system images")
struct VisionCapabilityTests {

    @Test("displayName covers every case")
    func displayNameComplete() {
        for capability in VisionCapability.allCases {
            #expect(!capability.displayName.isEmpty, "displayName missing for \(capability)")
        }
    }

    @Test("systemImage covers every case")
    func systemImageComplete() {
        for capability in VisionCapability.allCases {
            #expect(!capability.systemImage.isEmpty, "systemImage missing for \(capability)")
        }
    }

    @Test("displayName values are stable contract")
    func displayNameStable() {
        // Pinned strings — UI screens depend on these. A rename should
        // be visible in a test diff.
        #expect(VisionCapability.ocr.displayName == "Text recognition")
        #expect(VisionCapability.foregroundMask.displayName == "Subject lift")
        #expect(VisionCapability.depth.displayName == "Depth estimation")
        #expect(VisionCapability.documentRecognition.displayName == "Document layout")
        #expect(VisionCapability.faceDetection.displayName == "Face detection")
    }

    @Test("rawValue round-trips through Codable")
    func codable() throws {
        for capability in VisionCapability.allCases {
            let data = try JSONEncoder().encode(capability)
            let decoded = try JSONDecoder().decode(VisionCapability.self, from: data)
            #expect(decoded == capability)
        }
    }
}

@Suite("VisionProviderError descriptions")
struct VisionProviderErrorTests {

    @Test("Each error case describes itself with the documented prefix")
    func errorDescriptions() {
        #expect(
            VisionProviderError.unsupportedPlatform.description
                .contains("unavailable on this platform")
        )
        #expect(
            VisionProviderError.unsupportedOSVersion("Depth estimation").description
                .contains("Depth estimation")
        )
        #expect(
            VisionProviderError.invalidImage.description.contains("Could not decode")
        )
        #expect(
            VisionProviderError.requestFailed("boom").description.contains("boom")
        )
    }
}
