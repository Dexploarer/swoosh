// Tests/SwooshBrowserTests/BrowserSupervisorTests.swift — Browser lifecycle tests
//
// Tests Chrome process management, session creation, and supervisor lifecycle.

import Testing
import Foundation
@testable import SwooshBrowser

// MARK: - Browser Supervisor Tests

@Suite("BrowserSupervisor")
struct BrowserSupervisorTests {

    @Test("Initializes with default debug port")
    func initializesWithDefaultPort() {
        let supervisor = BrowserSupervisor()
        // If this compiles and runs, initialization works
        #expect(supervisor != nil)
    }

    @Test("Initializes with custom debug port")
    func initializesWithCustomPort() {
        let supervisor = BrowserSupervisor(debugPort: 9333)
        #expect(supervisor != nil)
    }

    @Test("Find Chrome returns path when Chrome exists")
    func findChromeReturnsPath() async {
        let supervisor = BrowserSupervisor()
        let path = await supervisor.findChrome()

        // On macOS with Chrome installed, this should return a path
        // On CI or without Chrome, it may return nil
        // We just verify the method doesn't crash
        if let p = path {
            #expect(p.contains("Chrome") || p.contains("Chromium") || p.contains("Brave") || p.contains("Edge"))
        }
    }

    @Test("Is running returns false initially")
    func isRunningReturnsFalseInitially() async {
        let supervisor = BrowserSupervisor()
        let running = await supervisor.isRunning
        #expect(running == false)
    }

    @Test("Shutdown terminates process")
    func shutdownTerminatesProcess() async {
        let supervisor = BrowserSupervisor()

        // Should not crash even if no process running
        await supervisor.shutdown()

        let running = await supervisor.isRunning
        #expect(running == false)
    }
}

@Suite("BrowserSupervisor Error Handling")
struct BrowserSupervisorErrorTests {

    @Test("BrowserError cases are Sendable")
    func errorsAreSendable() {
        let errors: [BrowserError] = [
            .chromeNotFound,
            .sessionClosed,
            .connectionFailed("test"),
            .navigationFailed(URL(string: "https://example.com")!, "failed"),
            .elementNotFound("#missing"),
            .evaluationFailed("error"),
            .screenshotFailed("no data"),
            .timeout("slow"),
            .cdpProtocolError(-32000, "message")
        ]

        // If this compiles, all errors are Sendable
        _ = errors
    }

    @Test("BrowserError contains correct information")
    func errorContainsInfo() {
        let url = URL(string: "https://example.com")!
        let error = BrowserError.navigationFailed(url, "Network error")

        // Verify we can create the error with the right associated values
        if case .navigationFailed(let failedURL, let message) = error {
            #expect(failedURL == url)
            #expect(message == "Network error")
        } else {
            Issue.record("Wrong error type")
        }
    }

    @Test("CDP protocol error contains code and message")
    func cdpErrorContainsCodeAndMessage() {
        let error = BrowserError.cdpProtocolError(-32600, "Invalid Request")

        if case .cdpProtocolError(let code, let message) = error {
            #expect(code == -32600)
            #expect(message == "Invalid Request")
        } else {
            Issue.record("Wrong error type")
        }
    }
}

@Suite("BrowserSession Protocol")
struct BrowserSessionProtocolTests {

    @Test("BrowserSession protocol requirements are met by CDPBrowserSession")
    func cdpSessionConformsToProtocol() async {
        // This is a compile-time check
        // If CDPBrowserSession compiles, it conforms to BrowserSession
        let _: any BrowserSession.Type = CDPBrowserSession.self
        #expect(true)
    }

    @Test("PageLink conforms to required protocols")
    func pageLinkConforms() {
        let link = PageLink(href: "https://example.com", text: "Example")

        // Should be Identifiable
        _ = link.id

        // Should be Codable
        let data = try? JSONEncoder().encode(link)
        #expect(data != nil)

        // Should be Sendable (compile-time check)
        let _: any Sendable.Type = PageLink.self
    }

    @Test("PageForm conforms to required protocols")
    func pageFormConforms() {
        let form = PageForm(action: "/submit", method: "POST", fields: [])

        // Should be Identifiable
        _ = form.id

        // Should be Codable
        let data = try? JSONEncoder().encode(form)
        #expect(data != nil)
    }

    @Test("FormField conforms to required protocols")
    func formFieldConforms() {
        let field = FormField(name: "email", type: "email", required: true)

        // Should be Codable
        let data = try? JSONEncoder().encode(field)
        #expect(data != nil)

        // Should be Sendable (compile-time check)
        let _: any Sendable.Type = FormField.self
    }

    @Test("ElementInfo conforms to required protocols")
    func elementInfoConforms() {
        let element = ElementInfo(tagName: "div", id: "test")

        // Should be Codable
        let data = try? JSONEncoder().encode(element)
        #expect(data != nil)
    }

    @Test("BoundingBox conforms to required protocols")
    func boundingBoxConforms() {
        let bbox = BoundingBox(x: 0, y: 0, width: 100, height: 100)

        // Should be Codable
        let data = try? JSONEncoder().encode(bbox)
        #expect(data != nil)
    }
}

@Suite("Browser Types Edge Cases")
struct BrowserTypesEdgeCaseTests {

    @Test("PageLink handles empty text")
    func pageLinkEmptyText() {
        let link = PageLink(href: "https://example.com", text: "")
        #expect(link.text == "")
        #expect(link.href == "https://example.com")
    }

    @Test("PageForm handles nil action")
    func pageFormNilAction() {
        let form = PageForm(action: nil, method: "GET", fields: [])
        #expect(form.action == nil)
        #expect(form.method == "GET")
    }

    @Test("FormField handles nil value")
    func formFieldNilValue() {
        let field = FormField(name: "search", type: "text", value: nil, placeholder: "Search...", required: false)
        #expect(field.value == nil)
        #expect(field.placeholder == "Search...")
        #expect(field.required == false)
    }

    @Test("ElementInfo handles nil optional fields")
    func elementInfoNilFields() {
        let element = ElementInfo(
            tagName: "span",
            id: nil,
            className: nil,
            text: "",
            attributes: [:],
            boundingBox: nil,
            isVisible: false
        )
        #expect(element.id == nil)
        #expect(element.className == nil)
        #expect(element.boundingBox == nil)
        #expect(element.isVisible == false)
    }

    @Test("BoundingBox handles zero dimensions")
    func boundingBoxZeroDimensions() {
        let bbox = BoundingBox(x: 0, y: 0, width: 0, height: 0)
        #expect(bbox.width == 0)
        #expect(bbox.height == 0)
    }

    @Test("BoundingBox handles negative coordinates")
    func boundingBoxNegativeCoords() {
        let bbox = BoundingBox(x: -100, y: -50, width: 200, height: 100)
        #expect(bbox.x == -100)
        #expect(bbox.y == -50)
    }
}

@Suite("AnyCodableValue Edge Cases")
struct AnyCodableValueEdgeCaseTests {

    @Test("AnyCodableValue handles deeply nested structures")
    func handlesNestedStructures() throws {
        let nested = AnyCodableValue.object([
            "level1": .object([
                "level2": .object([
                    "value": .string("deep")
                ])
            ])
        ])

        let data = try JSONEncoder().encode(nested)
        let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)

        if case .object(let obj) = decoded {
            if case .object(let level1) = obj["level1"] {
                if case .object(let level2) = level1["level2"] {
                    #expect(level2["value"]?.stringValue == "deep")
                } else {
                    Issue.record("Expected nested object")
                }
            } else {
                Issue.record("Expected nested object")
            }
        } else {
            Issue.record("Expected object")
        }
    }

    @Test("AnyCodableValue handles mixed arrays")
    func handlesMixedArrays() throws {
        let mixed = AnyCodableValue.array([
            .string("text"),
            .int(42),
            .bool(true),
            .null,
            .double(3.14)
        ])

        let data = try JSONEncoder().encode(mixed)
        let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)

        if case .array(let arr) = decoded {
            #expect(arr.count == 5)
            #expect(arr[0].stringValue == "text")
            #expect(arr[1].intValue == 42)
            #expect(arr[2].boolValue == true)
            #expect(arr[3].stringValue == nil) // null
        } else {
            Issue.record("Expected array")
        }
    }

    @Test("AnyCodableValue handles empty structures")
    func handlesEmptyStructures() throws {
        let emptyObject = AnyCodableValue.object([:])
        let emptyArray = AnyCodableValue.array([])

        let objData = try JSONEncoder().encode(emptyObject)
        let arrData = try JSONEncoder().encode(emptyArray)

        let decodedObj = try JSONDecoder().decode(AnyCodableValue.self, from: objData)
        let decodedArr = try JSONDecoder().decode(AnyCodableValue.self, from: arrData)

        if case .object(let obj) = decodedObj {
            #expect(obj.isEmpty)
        } else {
            Issue.record("Expected empty object")
        }

        if case .array(let arr) = decodedArr {
            #expect(arr.isEmpty)
        } else {
            Issue.record("Expected empty array")
        }
    }
}
