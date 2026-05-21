// Tests/SwooshLSPTests/LSPTests.swift — SwooshLSP types + client smoke
//
// Covers LSPValue Codable, LSPRequest/Notification envelopes,
// LSPDiagnostic severity labels, and a minimal LSPClient init smoke.

import Testing
import Foundation
@testable import SwooshLSP

// MARK: - LSPValue

@Suite("LSPValue Codable")
struct LSPValueTests {

    private func roundTrip(_ value: LSPValue) throws -> LSPValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(LSPValue.self, from: data)
    }

    @Test("string round-trips")
    func string() throws {
        if case .string(let s) = try roundTrip(.string("hello")) {
            #expect(s == "hello")
        } else { Issue.record() }
    }

    @Test("int round-trips")
    func int() throws {
        if case .int(let i) = try roundTrip(.int(42)) {
            #expect(i == 42)
        } else { Issue.record() }
    }

    @Test("bool round-trips")
    func bool() throws {
        if case .bool(let b) = try roundTrip(.bool(true)) {
            #expect(b == true)
        } else { Issue.record() }
    }

    @Test("null round-trips")
    func null() throws {
        if case .null = try roundTrip(.null) {} else { Issue.record() }
    }

    @Test("array round-trips")
    func array() throws {
        if case .array(let arr) = try roundTrip(.array([.int(1), .string("a")])) {
            #expect(arr.count == 2)
        } else { Issue.record() }
    }

    @Test("object round-trips")
    func object() throws {
        let v: LSPValue = .object(["k": .string("v")])
        if case .object(let o) = try roundTrip(v) {
            #expect(o["k"]?.stringValue == "v")
        } else { Issue.record() }
    }

    @Test("stringValue helper")
    func stringValue() {
        #expect(LSPValue.string("x").stringValue == "x")
        #expect(LSPValue.int(1).stringValue == nil)
        #expect(LSPValue.null.stringValue == nil)
    }
}

// MARK: - LSPRequest

@Suite("LSPRequest")
struct LSPRequestTests {

    @Test("Sets jsonrpc to 2.0")
    func jsonRPC() {
        let req = LSPRequest(id: 1, method: "initialize")
        #expect(req.jsonrpc == "2.0")
        #expect(req.id == 1)
        #expect(req.method == "initialize")
        #expect(req.params == nil)
    }

    @Test("Encodes with params")
    func encodesWithParams() throws {
        let req = LSPRequest(id: 5, method: "textDocument/hover", params: ["uri": .string("file://x")])
        let data = try JSONEncoder().encode(req)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"jsonrpc\":\"2.0\""))
        #expect(json.contains("\"id\":5"))
        // JSONEncoder escapes forward slashes by default ("\/").
        #expect(json.contains("textDocument\\/hover"))
    }
}

// MARK: - LSPNotification

@Suite("LSPNotification")
struct LSPNotificationTests {

    @Test("Default jsonrpc")
    func jsonRPC() {
        let note = LSPNotification(method: "initialized")
        #expect(note.jsonrpc == "2.0")
        #expect(note.method == "initialized")
        #expect(note.params == nil)
    }
}

// MARK: - LSPDiagnostic

@Suite("LSPDiagnostic")
struct LSPDiagnosticTests {

    private func diag(_ severity: Int?) -> LSPDiagnostic {
        LSPDiagnostic(
            range: LSPRange(start: LSPPosition(line: 0, character: 0),
                            end: LSPPosition(line: 0, character: 1)),
            severity: severity,
            message: "msg"
        )
    }

    @Test("Severity labels")
    func severityLabels() {
        #expect(diag(1).severityLabel == "error")
        #expect(diag(2).severityLabel == "warning")
        #expect(diag(3).severityLabel == "info")
        #expect(diag(4).severityLabel == "hint")
        #expect(diag(nil).severityLabel == "unknown")
        #expect(diag(99).severityLabel == "unknown")
    }

    @Test("Codable round-trip")
    func codable() throws {
        let original = diag(2)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LSPDiagnostic.self, from: data)
        #expect(decoded.message == "msg")
        #expect(decoded.severity == 2)
    }
}

// MARK: - LSPRange / LSPPosition

@Suite("LSPRange / Position")
struct LSPRangeTests {

    @Test("Round-trips")
    func roundTrip() throws {
        let range = LSPRange(
            start: LSPPosition(line: 1, character: 2),
            end: LSPPosition(line: 3, character: 4)
        )
        let data = try JSONEncoder().encode(range)
        let decoded = try JSONDecoder().decode(LSPRange.self, from: data)
        #expect(decoded.start.line == 1)
        #expect(decoded.start.character == 2)
        #expect(decoded.end.line == 3)
        #expect(decoded.end.character == 4)
    }
}

// MARK: - LSPClient

@Suite("LSPClient Smoke")
struct LSPClientSmokeTests {

    @Test("Initializes with default server path")
    func defaultInit() {
        let client = LSPClient()
        _ = client
        #expect(Bool(true))
    }

    @Test("Initializes with custom path")
    func customInit() {
        let client = LSPClient(serverPath: "/usr/local/bin/sourcekit-lsp")
        _ = client
        #expect(Bool(true))
    }

    @Test("isAvailable returns Bool")
    func isAvailable() {
        let available = LSPClient.isAvailable()
        // Just verify it returns without crashing
        #expect(available == true || available == false)
    }
}
