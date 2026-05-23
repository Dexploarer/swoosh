// Tests/SwooshLocalVoiceTests/LocalVoiceCatalogTests.swift
// Version: 0.9R
//
// Validates the on-device voice catalog: IDs are unique, URLs are
// well-formed Hugging Face paths, byte estimates are positive, and
// every advertised model is fetchable by id.

import XCTest
@testable import SwooshLocalVoice

final class LocalVoiceCatalogTests: XCTestCase {

    func test_catalog_isNonEmpty() {
        XCTAssertFalse(LocalVoiceCatalog.all.isEmpty, "Catalog must ship at least one model")
    }

    func test_catalog_idsAreUnique() {
        let ids = LocalVoiceCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Duplicate model IDs would break VoiceRouter routing")
    }

    func test_catalog_lookupByID() {
        for model in LocalVoiceCatalog.all {
            XCTAssertEqual(LocalVoiceCatalog.model(id: model.id)?.id, model.id)
        }
        XCTAssertNil(LocalVoiceCatalog.model(id: "does-not-exist"))
    }

    func test_catalog_urlsAreHuggingFace() {
        for model in LocalVoiceCatalog.all {
            XCTAssertEqual(
                model.downloadURL.host(percentEncoded: false), "huggingface.co",
                "All catalog URLs must resolve to huggingface.co (got \(model.downloadURL))"
            )
            XCTAssertEqual(model.downloadURL.scheme, "https")
        }
    }

    func test_catalog_estimatedBytesArePositive() {
        for model in LocalVoiceCatalog.all {
            XCTAssertGreaterThan(model.estimatedBytes, 0, "\(model.id) has non-positive size")
        }
    }

    func test_catalog_engineKindsAreKnown() {
        // Every catalog entry must declare a known engine kind so the
        // dispatcher's switch covers it.
        let known = Set(LocalVoiceModel.EngineKind.allCases)
        for model in LocalVoiceCatalog.all {
            XCTAssertTrue(known.contains(model.engineKind), "\(model.id) declares unknown engine kind")
        }
    }

    func test_catalog_kokoroEntry() {
        // Kokoro is the smallest, default model — guard its core attrs.
        let k = LocalVoiceCatalog.kokoro
        XCTAssertEqual(k.family, "Kokoro")
        XCTAssertLessThan(k.estimatedBytes, 500_000_000, "Kokoro must fit easily on iPhone")
        XCTAssertEqual(k.license, "Apache-2.0")
        XCTAssertEqual(LocalVoiceCatalog.defaultModel.id, k.id)
    }

    func test_catalog_omniVoiceEntry() {
        // OmniVoice is the multilingual / cloning play.
        let o = LocalVoiceCatalog.omniVoice
        XCTAssertEqual(o.family, "OmniVoice")
        XCTAssertTrue(o.supportsVoiceCloning, "OmniVoice catalog flag must advertise cloning")
        XCTAssertGreaterThan(o.languageCount, 100, "OmniVoice must advertise multilingual support")
    }
}
