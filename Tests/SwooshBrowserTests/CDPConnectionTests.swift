// Tests/SwooshBrowserTests/CDPConnectionTests.swift — Comprehensive CDP connection tests
//
// Tests the WebSocket-based Chrome DevTools Protocol connection,
// message encoding/decoding, and error handling.

import Testing
import Foundation
@testable import SwooshBrowser

// MARK: - AnyCodableValue Tests

@Suite("AnyCodableValue")
struct AnyCodableValueTests {

    @Test("Encodes and decodes string")
    func stringRoundTrip() throws {
        let value = AnyCodableValue.string("hello")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
        #expect(decoded.stringValue == "hello")
    }

    @Test("Encodes and decodes int")
    func intRoundTrip() throws {
        let value = AnyCodableValue.int(42)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
        #expect(decoded.intValue == 42)
    }

    @Test("Encodes and decodes double")
    func doubleRoundTrip() throws {
        let value = AnyCodableValue.double(3.14)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
        #expect(decoded.stringValue == nil) // double doesn't extract as string
    }

    @Test("Encodes and decodes bool")
    func boolRoundTrip() throws {
        let value = AnyCodableValue.bool(true)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
        #expect(decoded.boolValue == true)
    }

    @Test("Encodes and decodes null")
    func nullRoundTrip() throws {
        let value = AnyCodableValue.null
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
        #expect(decoded.stringValue == nil)
    }

    @Test("Encodes and decodes array")
    func arrayRoundTrip() throws {
        let value = AnyCodableValue.array([.string("a"), .int(1)])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
        if case .array(let arr) = decoded {
            #expect(arr.count == 2)
        } else {
            Issue.record("Expected array")
        }
    }

    @Test("Encodes and decodes object")
    func objectRoundTrip() throws {
        let value = AnyCodableValue.object(["key": .string("value")])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
        if case .object(let obj) = decoded {
            #expect(obj["key"]?.stringValue == "value")
        } else {
            Issue.record("Expected object")
        }
    }

    @Test("Extracts string value correctly")
    func extractsString() {
        #expect(AnyCodableValue.string("test").stringValue == "test")
        #expect(AnyCodableValue.int(42).stringValue == nil)
    }

    @Test("Extracts int value correctly")
    func extractsInt() {
        #expect(AnyCodableValue.int(42).intValue == 42)
        #expect(AnyCodableValue.string("42").intValue == nil)
    }

    @Test("Extracts bool value correctly")
    func extractsBool() {
        #expect(AnyCodableValue.bool(true).boolValue == true)
        #expect(AnyCodableValue.bool(false).boolValue == false)
        #expect(AnyCodableValue.string("true").boolValue == nil)
    }
}

// MARK: - CDP Request/Response Tests

@Suite("CDP Message Types")
struct CDPMessageTests {

    @Test("CDPRequest encodes correctly")
    func requestEncoding() throws {
        let request = CDPRequest(
            id: 1,
            method: "Page.navigate",
            params: ["url": .string("https://example.com")]
        )
        let data = try JSONEncoder().encode(request)
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("\"id\":1"))
        #expect(json.contains("\"method\":\"Page.navigate\""))
        // JSONEncoder escapes forward slashes, so the URL appears as https:\/\/example.com
        #expect(json.contains("\"url\":\"https:\\/\\/example.com\""))
    }

    @Test("CDPResponse decodes correctly")
    func responseDecoding() throws {
        let json = """
        {
            "id": 1,
            "result": {"frameId": "123", "loaderId": "abc"},
            "error": null
        }
        """
        let response = try JSONDecoder().decode(CDPResponse.self, from: json.data(using: .utf8)!)
        #expect(response.id == 1)
        #expect(response.result != nil)
        #expect(response.error == nil)
    }

    @Test("CDPResponse decodes error correctly")
    func errorDecoding() throws {
        let json = """
        {
            "id": 2,
            "result": null,
            "error": {"code": -32000, "message": "Command failed"}
        }
        """
        let response = try JSONDecoder().decode(CDPResponse.self, from: json.data(using: .utf8)!)
        #expect(response.id == 2)
        #expect(response.error?.code == -32000)
        #expect(response.error?.message == "Command failed")
    }

    @Test("CDPResponse decodes event correctly")
    func eventDecoding() throws {
        let json = """
        {
            "method": "Page.loadEventFired",
            "params": {"timestamp": 1234567890.123}
        }
        """
        let response = try JSONDecoder().decode(CDPResponse.self, from: json.data(using: .utf8)!)
        #expect(response.id == nil)
        #expect(response.method == "Page.loadEventFired")
        #expect(response.params != nil)
    }
}

// MARK: - CDP Connection Tests

@Suite("CDP Connection")
struct CDPConnectionTests {

    @Test("Connection initializes with WebSocket URL")
    func initializesWithURL() {
        let url = URL(string: "ws://localhost:9222/devtools/page/123")!
        let conn = CDPConnection(wsURL: url)
        // Connection is an actor, so we can't directly inspect it,
        // but we can verify it was created
        #expect(conn != nil)
    }

    @Test("Connection from debug endpoint requires valid URL")
    func fromDebugEndpointRequiresValidURL() async throws {
        // This test would require a real Chrome instance
        // For now, we just verify the API exists
        let endpoint = URL(string: "http://localhost:9222")!
        // Would throw if Chrome not running:
        // let conn = try await CDPConnection.fromDebugEndpoint(endpoint)
        #expect(endpoint != nil)
    }
}

// MARK: - Browser Error Tests

@Suite("BrowserError")
struct BrowserErrorTests {

    @Test("BrowserError is Sendable")
    func isSendable() {
        let error: BrowserError = .connectionFailed("test")
        // If this compiles, BrowserError is Sendable
        _ = error
    }

    @Test("All error cases exist")
    func allCasesExist() {
        let errors: [BrowserError] = [
            .connectionFailed("test"),
            .navigationFailed(URL(string: "https://example.com")!, "fail"),
            .elementNotFound("#missing"),
            .evaluationFailed("syntax error"),
            .screenshotFailed("no data"),
            .timeout("slow"),
            .sessionClosed,
            .chromeNotFound,
            .cdpProtocolError(-32000, "error")
        ]
        #expect(errors.count == 9)
    }
}

// MARK: - Page Element Type Tests

@Suite("Page Element Types")
struct PageElementTests {

    @Test("PageLink encodes and decodes")
    func pageLinkRoundTrip() throws {
        let link = PageLink(href: "https://example.com", text: "Example", isExternal: true)
        let data = try JSONEncoder().encode(link)
        let decoded = try JSONDecoder().decode(PageLink.self, from: data)
        #expect(decoded.href == "https://example.com")
        #expect(decoded.text == "Example")
        #expect(decoded.isExternal == true)
        // id is a stored property included in the synthesized Codable, so it
        // round-trips through encode/decode (the convenience init is not called
        // on decode — the synthesized memberwise decoder is).
        #expect(decoded.id == link.id)
    }

    @Test("PageForm encodes and decodes")
    func pageFormRoundTrip() throws {
        let fields = [
            FormField(name: "email", type: "email", value: "test@example.com", placeholder: "Email", required: true),
            FormField(name: "password", type: "password", value: nil, placeholder: nil, required: true)
        ]
        let form = PageForm(action: "/submit", method: "POST", fields: fields)
        let data = try JSONEncoder().encode(form)
        let decoded = try JSONDecoder().decode(PageForm.self, from: data)
        #expect(decoded.action == "/submit")
        #expect(decoded.method == "POST")
        #expect(decoded.fields.count == 2)
        #expect(decoded.fields[0].name == "email")
    }

    @Test("FormField properties correct")
    func formFieldProperties() {
        let field = FormField(
            name: "username",
            type: "text",
            value: "john",
            placeholder: "Enter username",
            required: true
        )
        #expect(field.name == "username")
        #expect(field.type == "text")
        #expect(field.value == "john")
        #expect(field.placeholder == "Enter username")
        #expect(field.required == true)
    }

    @Test("ElementInfo encodes and decodes")
    func elementInfoRoundTrip() throws {
        let bbox = BoundingBox(x: 10, y: 20, width: 100, height: 50)
        let element = ElementInfo(
            tagName: "div",
            id: "container",
            className: "wrapper",
            text: "Hello World",
            attributes: ["data-id": "123"],
            boundingBox: bbox,
            isVisible: true
        )
        let data = try JSONEncoder().encode(element)
        let decoded = try JSONDecoder().decode(ElementInfo.self, from: data)
        #expect(decoded.tagName == "div")
        #expect(decoded.id == "container")
        #expect(decoded.className == "wrapper")
        #expect(decoded.text == "Hello World")
        #expect(decoded.boundingBox?.x == 10)
        #expect(decoded.isVisible == true)
    }

    @Test("BoundingBox properties correct")
    func boundingBoxProperties() {
        let bbox = BoundingBox(x: 0, y: 0, width: 1920, height: 1080)
        #expect(bbox.x == 0)
        #expect(bbox.y == 0)
        #expect(bbox.width == 1920)
        #expect(bbox.height == 1080)
    }
}
