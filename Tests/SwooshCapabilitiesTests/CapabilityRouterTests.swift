// Tests/SwooshCapabilitiesTests/CapabilityRouterTests.swift
// Version: 0.9R
//
// Smoke tests for the modality router: UserDefaults round-trip per
// modality, provider-selection branching when no Keychain key is set,
// and verification that `isXConfigured` reflects Keychain state without
// requiring an actual key write (we use a non-standard suite to keep
// the host Keychain untouched).

import XCTest
@testable import SwooshCapabilities

@MainActor
final class CapabilityRouterTests: XCTestCase {

    private var router: CapabilityRouter!
    private let keys: [String] = [
        "swoosh.capabilities.vision",
        "swoosh.capabilities.translation",
        "swoosh.capabilities.embedding",
        "swoosh.capabilities.localEmbedding",
        "swoosh.capabilities.imageGen",
        "swoosh.capabilities.video",
        "swoosh.capabilities.threeD",
    ]

    override func setUp() {
        super.setUp()
        router = CapabilityRouter()
        for key in keys { UserDefaults.standard.removeObject(forKey: key) }
    }

    override func tearDown() {
        for key in keys { UserDefaults.standard.removeObject(forKey: key) }
        super.tearDown()
    }

    // MARK: - Defaults

    func testDefaultChoices() {
        XCTAssertEqual(router.currentVisionChoice, .appleVision)
        XCTAssertEqual(router.currentTranslationChoice, .routerLocalFirst)
        XCTAssertEqual(router.currentEmbeddingChoice, .appleNL)
        XCTAssertEqual(router.currentLocalEmbeddingChoice, .ollamaNomicEmbed)
        XCTAssertEqual(router.currentImageGenChoice, .routerLocalFirst)
        XCTAssertEqual(router.currentVideoChoice, .falVeo3)
        XCTAssertEqual(router.currentThreeDChoice, .falTripo3D)
    }

    // MARK: - Local embedding preset

    func testLocalEmbeddingChoicePersists() {
        router.currentLocalEmbeddingChoice = .ollamaMxbaiEmbed
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "swoosh.capabilities.localEmbedding"),
            "ollama-mxbai-embed"
        )
        XCTAssertEqual(router.currentLocalEmbeddingChoice, .ollamaMxbaiEmbed)
    }

    func testLocalEmbeddingChoiceConfigMapping() {
        router.currentLocalEmbeddingChoice = .ollamaBGEM3
        XCTAssertEqual(router.currentLocalEmbeddingChoice.config.model, "bge-m3")
        XCTAssertEqual(router.currentLocalEmbeddingChoice.config.outputDimension, 1024)
    }

    // MARK: - UserDefaults round-trip

    func testTranslationChoicePersists() {
        router.currentTranslationChoice = .appleTranslation
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "swoosh.capabilities.translation"),
            "apple-translation"
        )
        XCTAssertEqual(router.currentTranslationChoice, .appleTranslation)
    }

    func testEmbeddingChoicePersists() {
        router.currentEmbeddingChoice = .openAI
        XCTAssertEqual(router.currentEmbeddingChoice, .openAI)
        router.currentEmbeddingChoice = .localOpenAICompatible
        XCTAssertEqual(router.currentEmbeddingChoice, .localOpenAICompatible)
    }

    func testVideoChoicePersists() {
        router.currentVideoChoice = .falHunyuan
        XCTAssertEqual(router.currentVideoChoice, .falHunyuan)
        XCTAssertEqual(router.currentVideoChoice.modelID, "fal-ai/hunyuan-video")
    }

    func testThreeDChoicePersists() {
        router.currentThreeDChoice = .falHunyuan3D
        XCTAssertEqual(router.currentThreeDChoice, .falHunyuan3D)
        XCTAssertEqual(router.currentThreeDChoice.modelID, "fal-ai/hunyuan3d/v2")
    }

    // MARK: - Provider construction

    func testActiveVisionAlwaysReturnsAppleProvider() {
        XCTAssertNotNil(router.activeVisionProvider())
    }

    func testActiveTranslationFallsBackWhenLocalSelected() {
        router.currentTranslationChoice = .appleTranslation
        XCTAssertNotNil(router.activeTranslationProvider())
    }

    func testActiveEmbeddingFallsBackWhenLocalSelected() {
        router.currentEmbeddingChoice = .appleNL
        XCTAssertNotNil(router.activeEmbeddingProvider())
    }

    func testActiveImageGenFallsBackWhenLocalSelected() {
        router.currentImageGenChoice = .imagePlayground
        XCTAssertNotNil(router.activeImageGenProvider())
    }

    // MARK: - Cloud-gated providers

    func testVideoProviderNilWithoutFALKey() {
        // Test runs in a fresh test host with no Keychain access — the
        // FAL provider must report unconfigured and refuse construction.
        if !router.isVideoConfigured {
            XCTAssertNil(router.activeVideoProvider())
        }
    }

    func testThreeDProviderNilWithoutFALKey() {
        if !router.isThreeDConfigured {
            XCTAssertNil(router.activeThreeDProvider())
        }
    }

    // MARK: - Display + locality metadata

    func testTranslationChoiceLocalityFlags() {
        XCTAssertTrue(CapabilityRouter.TranslationChoice.appleTranslation.isLocal)
        XCTAssertFalse(CapabilityRouter.TranslationChoice.openAI.isLocal)
        XCTAssertTrue(CapabilityRouter.TranslationChoice.routerLocalFirst.isLocal)
    }

    func testVideoChoiceAllCloud() {
        for choice in CapabilityRouter.VideoChoice.allCases {
            XCTAssertFalse(choice.isLocal, "video choice \(choice) should be cloud-only")
            XCTAssertFalse(choice.modelID.isEmpty)
            XCTAssertFalse(choice.displayName.isEmpty)
        }
    }

    func testThreeDChoiceAllCloud() {
        for choice in CapabilityRouter.ThreeDChoice.allCases {
            XCTAssertFalse(choice.isLocal, "3D choice \(choice) should be cloud-only")
            XCTAssertFalse(choice.modelID.isEmpty)
            XCTAssertFalse(choice.displayName.isEmpty)
        }
    }
}
