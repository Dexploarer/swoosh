// Tests/SwooshVisionTests/AppleVisionProviderTests.swift — 0.9S
//
// `AppleVisionProvider` exposes two non-runtime contracts that we want
// pinned with tests so a future Apple-OS bump (or a typo in the
// `@available` guard) is visible: the advertised `supportedCapabilities`
// matrix and the honest-refusal semantics of `depthMap`. We also pin
// the default-extension forwarding on `VisionProviding`.

import Foundation
import Testing
@testable import SwooshVision

@Suite("AppleVisionProvider — supportedCapabilities contract")
struct AppleVisionSupportedCapabilitiesTests {

    @Test("Identity surface is stable")
    func identity() {
        let provider = AppleVisionProvider()
        #expect(provider.id == "apple-vision")
        #expect(provider.displayName == "Apple Vision (on-device)")
        #expect(provider.isLocal)
    }

    @Test(".depth is never advertised — depthMap intentionally refuses")
    func depthOmittedFromCapabilitySet() {
        let provider = AppleVisionProvider()
        let caps = provider.supportedCapabilities()
        #expect(!caps.contains(.depth),
                "supportedCapabilities must not advertise .depth while depthMap throws unsupportedOSVersion")
    }

    @Test("On platforms where Vision builds, OCR is always advertised")
    func ocrAlwaysAdvertised() {
        #if canImport(Vision)
        let caps = AppleVisionProvider().supportedCapabilities()
        #expect(caps.contains(.ocr))
        #expect(caps.contains(.foregroundMask))
        #expect(caps.contains(.faceDetection))
        #endif
    }
}

@Suite("AppleVisionProvider — honest refusal for unsupported paths")
struct AppleVisionHonestRefusalTests {

    @Test("depthMap always throws unsupportedOSVersion — never returns empty bytes")
    func depthMapAlwaysThrows() async throws {
        let provider = AppleVisionProvider()
        do {
            _ = try await provider.depthMap(from: Data())
            Issue.record("Expected depthMap to throw")
        } catch let error as VisionProviderError {
            switch error {
            case .unsupportedOSVersion(let cap):
                #expect(cap == "Depth estimation")
            default:
                Issue.record("Wrong VisionProviderError case: \(error)")
            }
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }
}

@Suite("VisionProviding default extensions forward to language-aware overloads")
struct VisionProvidingDefaultsTests {

    /// Stub that records the language array each call site forwarded so
    /// we can assert the default extension's English-locale default.
    private actor StubVisionProvider: VisionProviding {
        nonisolated let id = "stub"
        nonisolated let displayName = "Stub"
        nonisolated let isLocal = true

        private(set) var recognizeTextCalls: [[String]] = []
        private(set) var recognizeDocumentCalls: [[String]] = []

        nonisolated func supportedCapabilities() -> Set<VisionCapability> { [] }

        func recognizeText(in imageData: Data, languages: [String]) async throws -> [VisionTextBlock] {
            recognizeTextCalls.append(languages)
            return []
        }

        func subjectMask(in imageData: Data) async throws -> VisionMaskResult {
            VisionMaskResult(pngData: Data(), subjectCount: 0)
        }

        func depthMap(from imageData: Data) async throws -> VisionDepthResult {
            VisionDepthResult(pngData: Data(), width: 0, height: 0)
        }

        func recognizeDocument(in imageData: Data, languages: [String]) async throws -> VisionDocumentResult {
            recognizeDocumentCalls.append(languages)
            return VisionDocumentResult(plainText: "", paragraphs: [], tables: [])
        }

        func detectFaces(in imageData: Data) async throws -> [VisionFace] { [] }
    }

    @Test("Default recognizeText(in:) forwards [\"en-US\"]")
    func defaultRecognizeTextLanguage() async throws {
        let stub = StubVisionProvider()
        _ = try await stub.recognizeText(in: Data())
        let calls = await stub.recognizeTextCalls
        #expect(calls.count == 1)
        #expect(calls.first == ["en-US"])
    }

    @Test("Default recognizeDocument(in:) forwards [\"en-US\"]")
    func defaultRecognizeDocumentLanguage() async throws {
        let stub = StubVisionProvider()
        _ = try await stub.recognizeDocument(in: Data())
        let calls = await stub.recognizeDocumentCalls
        #expect(calls.count == 1)
        #expect(calls.first == ["en-US"])
    }
}

@Suite("SwooshVision.defaultProvider")
struct SwooshVisionDefaultProviderTests {

    @Test("Returns AppleVisionProvider")
    func returnsApple() {
        let provider = SwooshVision.defaultProvider()
        #expect(provider.id == "apple-vision")
    }
}
