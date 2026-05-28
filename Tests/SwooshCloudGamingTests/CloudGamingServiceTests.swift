// SwooshCloudGamingTests/CloudGamingServiceTests.swift — Service registry tests
// 0.5A – May 2026

import XCTest
@testable import SwooshCloudGaming

final class CloudGamingServiceTests: XCTestCase {

    // ── Web services ────────────────────────────────────────────────

    func testAllWebServicesHaveValidURLs() {
        let services: [CloudGamingService] = [.xboxCloud, .geforceNow, .amazonLuna, .boosteroid]
        for service in services {
            XCTAssertFalse(service.streamURL.absoluteString.isEmpty,
                "\(service.displayName) has empty URL")
            XCTAssertTrue(service.streamURL.absoluteString.hasPrefix("https://"),
                "\(service.displayName) URL doesn't use HTTPS: \(service.streamURL)")
        }
    }

    func testAllServicesHaveDisplayNames() {
        let services: [CloudGamingService] = [.xboxCloud, .geforceNow, .amazonLuna, .boosteroid]
        for service in services {
            XCTAssertFalse(service.displayName.isEmpty)
        }
    }

    func testAllServicesHaveIcons() {
        let services: [CloudGamingService] = [.xboxCloud, .geforceNow, .amazonLuna, .boosteroid]
        for service in services {
            XCTAssertFalse(service.iconName.isEmpty)
        }
    }

    func testXboxHasUserAgentOverride() {
        XCTAssertNotNil(CloudGamingService.xboxCloud.userAgentOverride)
        XCTAssertTrue(
            CloudGamingService.xboxCloud.userAgentOverride!.contains("Edg"),
            "Xbox UA override should mention Edge"
        )
    }

    func testXboxStreamURL() {
        let url = CloudGamingService.xboxCloud.streamURL
        XCTAssertTrue(url.host?.contains("xbox.com") == true,
            "Xbox URL should point to xbox.com, got: \(url)")
    }

    func testAccentColors() {
        let services: [CloudGamingService] = [.xboxCloud, .geforceNow, .amazonLuna, .boosteroid]
        for service in services {
            let hex = service.accentHex
            XCTAssertEqual(hex.count, 7, "\(service.displayName) accent hex should be 7 chars (#RRGGBB)")
        }
    }

    // ── Native sources ──────────────────────────────────────────────

    func testNativeSourceDisplayNames() {
        let sources: [NativeGameSource] = [.greenlight, .steamLink, .playstation, .localWindow]
        for source in sources {
            XCTAssertFalse(source.displayName.isEmpty)
            XCTAssertFalse(source.iconName.isEmpty)
        }
    }

    // ── GameSource enum ─────────────────────────────────────────────

    func testGameSourceWebVariant() {
        let source = GameSource.web(.xboxCloud)
        switch source {
        case .web(let service):
            XCTAssertEqual(service.displayName, CloudGamingService.xboxCloud.displayName)
        case .native:
            XCTFail("Expected .web variant")
        }
    }

    func testGameSourceNativeVariant() {
        let source = GameSource.native(.greenlight)
        switch source {
        case .web:
            XCTFail("Expected .native variant")
        case .native(let ns):
            XCTAssertEqual(ns, .greenlight)
        }
    }

    // ── Codable round-trip ──────────────────────────────────────────

    func testCloudGamingServiceCodable() throws {
        let original = CloudGamingService.xboxCloud
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CloudGamingService.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testNativeGameSourceCodable() throws {
        let original = NativeGameSource.greenlight
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NativeGameSource.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}
