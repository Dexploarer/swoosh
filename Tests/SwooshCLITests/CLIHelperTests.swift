// Tests/SwooshCLITests/CLIHelperTests.swift — Helpers extracted from the audit — 0.4A
//
// Covers the small CLI helpers split out of SwooshCommand / SetupCommands
// / ChatAdapterCommands so that the consolidated implementations have at
// least one assertion each:
//   - generateBearerToken (CLIBearerToken.swift)
//   - JSONEncoder.swooshCLI (CLIJSON.swift)
//   - CLIPairing.pairingPayload / localIPAddress / generateQRCode

import Testing
import Foundation
@testable import SwooshCLI

@Suite("CLI helpers — bearer token")
struct BearerTokenTests {
    @Test("generateBearerToken returns 64 lowercase hex characters")
    func bearerShape() throws {
        let token = try generateBearerToken()
        #expect(token.count == 64)
        let allowed = Set("0123456789abcdef")
        #expect(token.allSatisfy { allowed.contains($0) })
    }

    @Test("generateBearerToken is unique across consecutive calls")
    func bearerUniqueness() throws {
        var seen = Set<String>()
        for _ in 0..<16 {
            seen.insert(try generateBearerToken())
        }
        #expect(seen.count == 16)
    }
}

@Suite("CLI helpers — JSON encoder")
struct CLIJSONTests {
    @Test("swooshCLI encoder is pretty-printed and sorted")
    func jsonShape() throws {
        struct Foo: Encodable { let z: Int; let a: Int }
        let data = try JSONEncoder.swooshCLI.encode(Foo(z: 1, a: 2))
        let text = String(data: data, encoding: .utf8) ?? ""
        // Sorted keys: "a" appears before "z".
        let aIndex = try #require(text.firstIndex(of: "a"))
        let zIndex = try #require(text.firstIndex(of: "z"))
        #expect(aIndex < zIndex)
        // Pretty-printed: contains a newline.
        #expect(text.contains("\n"))
    }

    @Test("swooshCLI encoder uses ISO-8601 dates")
    func jsonDates() throws {
        struct WithDate: Encodable { let when: Date }
        let stamp = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14T22:13:20Z
        let data = try JSONEncoder.swooshCLI.encode(WithDate(when: stamp))
        let text = String(data: data, encoding: .utf8) ?? ""
        #expect(text.contains("2023-11-14T22:13:20Z"))
    }
}

@Suite("CLI helpers — pairing")
struct CLIPairingTests {
    @Test("pairingPayload renders iOS deep link with host/token")
    func payloadShape() throws {
        let payload = try #require(CLIPairing.pairingPayload(host: "http://1.2.3.4:8787", token: "abc123"))
        let components = try #require(URLComponents(string: payload))
        #expect(components.scheme == "swoosh")
        #expect(components.host == "pair")
        #expect(components.queryItems?.first(where: { $0.name == "host" })?.value == "http://1.2.3.4:8787")
        #expect(components.queryItems?.first(where: { $0.name == "token" })?.value == "abc123")
    }

    @Test("pairingPayload preserves reserved URL characters")
    func payloadRoundTrip() throws {
        let payload = try #require(CLIPairing.pairingPayload(host: "http://host.local:8787", token: "abc+123/="))
        let components = try #require(URLComponents(string: payload))
        #expect(components.queryItems?.first(where: { $0.name == "host" })?.value == "http://host.local:8787")
        #expect(components.queryItems?.first(where: { $0.name == "token" })?.value == "abc+123/=")
    }

    @Test("localIPAddress either returns a usable IPv4 or nil")
    func localIPSafe() throws {
        // Must not crash and must reject loopback/link-local results.
        guard let ip = CLIPairing.localIPAddress() else { return }
        #expect(!ip.hasPrefix("127."))
        #expect(!ip.hasPrefix("169."))
        // Coarse IPv4 shape check.
        let parts = ip.split(separator: ".")
        #expect(parts.count == 4)
    }

    @Test("generateQRCode tolerates being called on any platform")
    func qrSafeFallback() throws {
        // CoreImage may not be available in every CI environment; the
        // helper is contracted to return `nil` rather than crash.
        let result = CLIPairing.generateQRCode(from: "test payload")
        if let result {
            #expect(!result.isEmpty)
            #expect(result.contains("\n"))
        }
    }
}
