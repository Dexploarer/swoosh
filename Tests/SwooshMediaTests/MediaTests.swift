// Tests/SwooshMediaTests/MediaTests.swift — SwooshMedia
//
// Covers media pipeline value types, MediaRouter actor behavior, error
// handling, and ImageSize / ImageStyle presets. Real capability
// implementations (TTS, image gen, etc.) are not exercised because they
// shell out to system services.

import Testing
import Foundation
@testable import SwooshMedia

// MARK: - ImageSize / ImageStyle

@Suite("ImageSize")
struct ImageSizeTests {

    @Test("Presets have expected dimensions")
    func presets() {
        #expect(ImageSize.small.width == 256 && ImageSize.small.height == 256)
        #expect(ImageSize.medium.width == 512 && ImageSize.medium.height == 512)
        #expect(ImageSize.large.width == 1024 && ImageSize.large.height == 1024)
    }

    @Test("Codable round-trip")
    func codable() throws {
        let original = ImageSize(width: 800, height: 600)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ImageSize.self, from: data)
        #expect(decoded.width == 800)
        #expect(decoded.height == 600)
    }
}

@Suite("ImageStyle")
struct ImageStyleTests {

    @Test("All cases round-trip")
    func allCases() throws {
        for style in [ImageStyle.natural, .vivid, .artistic, .photographic, .sketch] {
            let data = try JSONEncoder().encode(style)
            let decoded = try JSONDecoder().decode(ImageStyle.self, from: data)
            #expect(decoded == style)
        }
    }
}

// MARK: - ImageAnalysis / DetectedObject

@Suite("ImageAnalysis")
struct ImageAnalysisTests {

    @Test("Default initialization")
    func defaults() {
        let analysis = ImageAnalysis(description: "a cat")
        #expect(analysis.description == "a cat")
        #expect(analysis.labels.isEmpty)
        #expect(analysis.confidence == 0)
        #expect(analysis.objects.isEmpty)
    }

    @Test("Codable round-trip")
    func roundTrip() throws {
        let obj = DetectedObject(label: "cat", confidence: 0.9, x: 10, y: 20, width: 30, height: 40)
        let original = ImageAnalysis(
            description: "a scene",
            labels: ["animal"],
            confidence: 0.85,
            objects: [obj]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ImageAnalysis.self, from: data)
        #expect(decoded.description == "a scene")
        #expect(decoded.labels == ["animal"])
        #expect(decoded.objects.count == 1)
        #expect(decoded.objects[0].label == "cat")
    }
}

@Suite("DetectedObject")
struct DetectedObjectTests {

    @Test("Default fields are zero")
    func defaults() {
        let obj = DetectedObject(label: "x")
        #expect(obj.label == "x")
        #expect(obj.confidence == 0)
        #expect(obj.x == 0)
        #expect(obj.y == 0)
        #expect(obj.width == 0)
        #expect(obj.height == 0)
    }
}

// MARK: - MediaError

@Suite("MediaError")
struct MediaErrorTests {

    @Test("Cases distinguish")
    func cases() {
        let notAvail: MediaError = .capabilityNotAvailable("audio.tts")
        let invalid: MediaError = .invalidRequest("expected tts")
        let failed: MediaError = .processingFailed("oom")

        switch notAvail {
        case .capabilityNotAvailable(let id): #expect(id == "audio.tts")
        default: Issue.record()
        }
        switch invalid {
        case .invalidRequest(let m): #expect(m == "expected tts")
        default: Issue.record()
        }
        switch failed {
        case .processingFailed(let m): #expect(m == "oom")
        default: Issue.record()
        }
    }
}

// MARK: - MediaRouter

private struct StubCapability: MediaCapability {
    let capabilityID: String
    let displayName: String = "stub"
    let availabilityValue: Bool
    let result: MediaResult

    var isAvailable: Bool { get async { availabilityValue } }

    func execute(_ request: MediaRequest) async throws -> MediaResult {
        result
    }
}

@Suite("MediaRouter")
struct MediaRouterTests {

    @Test("Empty router throws capabilityNotAvailable")
    func emptyThrows() async {
        let router = MediaRouter()
        await #expect(throws: MediaError.self) {
            _ = try await router.execute(.textToSpeech(text: "hi", voice: nil))
        }
    }

    @Test("Register and execute routes to matching capability")
    func routes() async throws {
        let router = MediaRouter()
        let stub = StubCapability(
            capabilityID: "audio.tts",
            availabilityValue: true,
            result: .text("ack")
        )
        await router.register(stub)

        let result = try await router.execute(.textToSpeech(text: "hello", voice: nil))
        if case .text(let s) = result {
            #expect(s == "ack")
        } else {
            Issue.record("expected .text result")
        }
    }

    @Test("Unavailable capability throws")
    func unavailableThrows() async {
        let router = MediaRouter()
        let stub = StubCapability(
            capabilityID: "audio.tts",
            availabilityValue: false,
            result: .text("never")
        )
        await router.register(stub)

        await #expect(throws: MediaError.self) {
            _ = try await router.execute(.textToSpeech(text: "hi", voice: nil))
        }
    }

    @Test("available() lists only available capabilities")
    func availableList() async {
        let router = MediaRouter()
        await router.register(StubCapability(capabilityID: "a", availabilityValue: true, result: .text("")))
        await router.register(StubCapability(capabilityID: "b", availabilityValue: false, result: .text("")))
        let list = await router.available()
        #expect(list.contains("a"))
        #expect(!list.contains("b"))
    }

    @Test("Request targeting routes through capability id")
    func capabilityIDRouting() async throws {
        let router = MediaRouter()
        await router.register(StubCapability(capabilityID: "vision.analyze", availabilityValue: true, result: .text("ok")))
        let result = try await router.execute(.analyzeImage(imageData: Data(), prompt: nil))
        if case .text(let s) = result {
            #expect(s == "ok")
        } else {
            Issue.record()
        }
    }
}
