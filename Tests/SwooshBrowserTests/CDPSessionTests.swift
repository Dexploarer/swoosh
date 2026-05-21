// Tests/SwooshBrowserTests/CDPSessionTests.swift — CDP Browser Session tests
//
// Tests the CDP browser session implementation including navigation,
// element interaction, form handling, and JavaScript evaluation.

import Testing
import Foundation
@testable import SwooshBrowser

// MARK: - Mock CDP Connection for Testing

actor MockCDPConnection: CDPConnecting {
    var sentCommands: [(method: String, params: [String: AnyCodableValue]?)] = []
    var mockResponses: [String: CDPResponse] = [:]
    var shouldFailNext = false
    var failWith: BrowserError?
    var didDisconnect = false

    func send(method: String, params: [String: AnyCodableValue]?) async throws -> CDPResponse {
        sentCommands.append((method, params))

        if let error = failWith {
            throw error
        }

        if let response = mockResponses[method] {
            return response
        }

        // Default success response
        return CDPResponse(
            id: 1,
            result: [:],
            error: nil,
            method: nil,
            params: nil
        )
    }

    func disconnect() async {
        didDisconnect = true
    }

    func setMockResponse(method: String, result: [String: AnyCodableValue]) {
        mockResponses[method] = CDPResponse(
            id: 1,
            result: result,
            error: nil,
            method: nil,
            params: nil
        )
    }

    func setMockEvaluationResult(_ result: String) {
        mockResponses["Runtime.evaluate"] = CDPResponse(
            id: 1,
            result: [
                "result": .object([
                    "value": .string(result),
                    "type": .string("string")
                ])
            ],
            error: nil,
            method: nil,
            params: nil
        )
    }

    func clearCommands() {
        sentCommands.removeAll()
    }
}

// MARK: - CDP Browser Session Tests

@Suite("CDPBrowserSession")
struct CDPBrowserSessionTests {

    @Test("Session initializes with unique ID")
    func sessionInitializes() async {
        let mockConn = MockCDPConnection()
        let session = CDPBrowserSession(connection: mockConn)

        #expect(await session.sessionID != "")
        #expect(await session.isActive == true)
    }

    @Test("Navigate sends Page.navigate command")
    func navigateSendsCommand() async throws {
        let mockConn = MockCDPConnection()
        let session = CDPBrowserSession(connection: mockConn)

        let url = URL(string: "https://example.com")!
        try await session.navigate(to: url)

        let commands = await mockConn.sentCommands
        #expect(commands.contains { $0.method == "Page.navigate" })
        #expect(await session.currentURL == url)
    }

    @Test("Go back sends Page.goBack command")
    func goBackSendsCommand() async throws {
        let mockConn = MockCDPConnection()
        let session = CDPBrowserSession(connection: mockConn)

        try await session.goBack()

        let commands = await mockConn.sentCommands
        #expect(commands.contains { $0.method == "Page.goBack" })
    }

    @Test("Go forward sends Page.goForward command")
    func goForwardSendsCommand() async throws {
        let mockConn = MockCDPConnection()
        let session = CDPBrowserSession(connection: mockConn)

        try await session.goForward()

        let commands = await mockConn.sentCommands
        #expect(commands.contains { $0.method == "Page.goForward" })
    }

    @Test("Reload sends Page.reload command")
    func reloadSendsCommand() async throws {
        let mockConn = MockCDPConnection()
        let session = CDPBrowserSession(connection: mockConn)

        try await session.reload()

        let commands = await mockConn.sentCommands
        #expect(commands.contains { $0.method == "Page.reload" })
    }

    @Test("Wait for load sleeps for specified duration")
    func waitForLoadSleeps() async throws {
        let mockConn = MockCDPConnection()
        let session = CDPBrowserSession(connection: mockConn)

        let start = Date()
        try await session.waitForLoad(timeout: 0.1)
        let elapsed = Date().timeIntervalSince(start)

        #expect(elapsed >= 0.1)
    }
}

@Suite("CDPBrowserSession Interactions")
struct CDPSessionInteractionTests {

    @Test("Click evaluates JavaScript click")
    func clickEvaluatesJS() async throws {
        let mockConn = MockCDPConnection()
        let session = CDPBrowserSession(connection: mockConn)

        try await session.click(selector: "#button")

        let commands = await mockConn.sentCommands
        let evalCommand = commands.first { $0.method == "Runtime.evaluate" }
        #expect(evalCommand != nil)
        let expression = evalCommand?.params?["expression"]?.stringValue
        #expect(expression?.contains("document.querySelector") == true)
        #expect(expression?.contains(".click()") == true)
    }

    @Test("Type sends focus, value, and input event")
    func typeSendsEvents() async throws {
        let mockConn = MockCDPConnection()
        let session = CDPBrowserSession(connection: mockConn)

        try await session.type(selector: "#input", text: "hello world")

        let commands = await mockConn.sentCommands
        let evalCommand = commands.first { $0.method == "Runtime.evaluate" }
        let expression = evalCommand?.params?["expression"]?.stringValue
        #expect(expression?.contains("focus()") == true)
        #expect(expression?.contains("value=") == true)
        #expect(expression?.contains("hello world") == true)
        #expect(expression?.contains("dispatchEvent") == true)
    }

    @Test("Type escapes single quotes in text")
    func typeEscapesQuotes() async throws {
        let mockConn = MockCDPConnection()
        let session = CDPBrowserSession(connection: mockConn)

        try await session.type(selector: "#input", text: "it's a test")

        let commands = await mockConn.sentCommands
        let evalCommand = commands.first { $0.method == "Runtime.evaluate" }
        let expression = evalCommand?.params?["expression"]?.stringValue
        #expect(expression?.contains("it\\'s a test") == true)
    }

    @Test("Clear clears value and dispatches event")
    func clearClearsValue() async throws {
        let mockConn = MockCDPConnection()
        let session = CDPBrowserSession(connection: mockConn)

        try await session.clear(selector: "#input")

        let commands = await mockConn.sentCommands
        let evalCommand = commands.first { $0.method == "Runtime.evaluate" }
        let expression = evalCommand?.params?["expression"]?.stringValue
        #expect(expression?.contains("e.value=''") == true)
    }

    @Test("Select sets value and dispatches change event")
    func selectSetsValue() async throws {
        let mockConn = MockCDPConnection()
        let session = CDPBrowserSession(connection: mockConn)

        try await session.select(selector: "#select", value: "option1")

        let commands = await mockConn.sentCommands
        let evalCommand = commands.first { $0.method == "Runtime.evaluate" }
        let expression = evalCommand?.params?["expression"]?.stringValue
        #expect(expression?.contains("change") == true)
        #expect(expression?.contains("option1") == true)
    }

    @Test("Scroll executes window.scrollBy")
    func scrollExecutesJS() async throws {
        let mockConn = MockCDPConnection()
        let session = CDPBrowserSession(connection: mockConn)

        try await session.scroll(x: 100, y: 200)

        let commands = await mockConn.sentCommands
        let evalCommand = commands.first { $0.method == "Runtime.evaluate" }
        let expression = evalCommand?.params?["expression"]?.stringValue
        #expect(expression == "window.scrollBy(100,200)")
    }

    @Test("Hover dispatches mouseover event")
    func hoverDispatchesEvent() async throws {
        let mockConn = MockCDPConnection()
        let session = CDPBrowserSession(connection: mockConn)

        try await session.hover(selector: "#element")

        let commands = await mockConn.sentCommands
        let evalCommand = commands.first { $0.method == "Runtime.evaluate" }
        let expression = evalCommand?.params?["expression"]?.stringValue
        #expect(expression?.contains("MouseEvent") == true)
        #expect(expression?.contains("mouseover") == true)
    }
}

@Suite("CDPBrowserSession Extraction")
struct CDPSessionExtractionTests {

    @Test("Screenshot sends Page.captureScreenshot")
    func screenshotSendsCommand() async throws {
        let mockConn = MockCDPConnection()
        // Set up mock base64 response
        await mockConn.setMockResponse(
            method: "Page.captureScreenshot",
            result: ["data": .string("iVBORw0KGgo=")] // minimal PNG base64
        )
        let session = CDPBrowserSession(connection: mockConn)

        let data = try await session.screenshot(fullPage: false)

        let commands = await mockConn.sentCommands
        let screenshotCmd = commands.first { $0.method == "Page.captureScreenshot" }
        #expect(screenshotCmd != nil)
        #expect(screenshotCmd?.params?["format"]?.stringValue == "png")
        #expect(data.count > 0)
    }

    @Test("Screenshot with fullPage sets captureBeyondViewport")
    func fullPageScreenshotSetsFlag() async throws {
        let mockConn = MockCDPConnection()
        await mockConn.setMockResponse(
            method: "Page.captureScreenshot",
            result: ["data": .string("iVBORw0KGgo=")]
        )
        let session = CDPBrowserSession(connection: mockConn)

        _ = try await session.screenshot(fullPage: true)

        let commands = await mockConn.sentCommands
        let screenshotCmd = commands.first { $0.method == "Page.captureScreenshot" }
        #expect(screenshotCmd?.params?["captureBeyondViewport"]?.boolValue == true)
    }

    @Test("Extract text evaluates document.body.innerText")
    func extractTextEvaluatesJS() async throws {
        let mockConn = MockCDPConnection()
        await mockConn.setMockEvaluationResult("Hello World")
        let session = CDPBrowserSession(connection: mockConn)

        let text = try await session.extractText()

        #expect(text == "Hello World")
        let commands = await mockConn.sentCommands
        let evalCmd = commands.first { $0.method == "Runtime.evaluate" }
        let expression = evalCmd?.params?["expression"]?.stringValue
        #expect(expression == "document.body.innerText")
    }

    @Test("Extract HTML evaluates document.documentElement.outerHTML")
    func extractHTMLEvaluatesJS() async throws {
        let mockConn = MockCDPConnection()
        await mockConn.setMockEvaluationResult("<html></html>")
        let session = CDPBrowserSession(connection: mockConn)

        let html = try await session.extractHTML()

        #expect(html == "<html></html>")
    }

    @Test("Extract links evaluates JavaScript and parses JSON")
    func extractLinksParsesJSON() async throws {
        let mockConn = MockCDPConnection()
        let linksJSON = """
        [{"href":"https://example.com","text":"Example","isExternal":true}]
        """
        await mockConn.setMockEvaluationResult(linksJSON)
        let session = CDPBrowserSession(connection: mockConn)

        let links = try await session.extractLinks()

        #expect(links.count == 1)
        #expect(links[0].href == "https://example.com")
        #expect(links[0].text == "Example")
        #expect(links[0].isExternal == true)
    }

    @Test("Extract forms evaluates JavaScript and parses JSON")
    func extractFormsParsesJSON() async throws {
        let mockConn = MockCDPConnection()
        let formsJSON = """
        [{"action":"/submit","method":"POST","fields":[{"name":"email","type":"email","value":"test@test.com","placeholder":null,"required":true}]}]
        """
        await mockConn.setMockEvaluationResult(formsJSON)
        let session = CDPBrowserSession(connection: mockConn)

        let forms = try await session.extractForms()

        #expect(forms.count == 1)
        #expect(forms[0].action == "/submit")
        #expect(forms[0].method == "POST")
        #expect(forms[0].fields.count == 1)
        #expect(forms[0].fields[0].name == "email")
    }

    @Test("Query selector returns element info")
    func querySelectorReturnsInfo() async throws {
        let mockConn = MockCDPConnection()
        let elementJSON = """
        {"tagName":"div","id":"test","className":"container","text":"Hello","attributes":{},"boundingBox":{"x":0,"y":0,"width":100,"height":50},"isVisible":true}
        """
        await mockConn.setMockEvaluationResult(elementJSON)
        let session = CDPBrowserSession(connection: mockConn)

        let element = try await session.querySelector("#test")

        #expect(element != nil)
        #expect(element?.tagName == "div")
        #expect(element?.id == "test")
        #expect(element?.boundingBox?.width == 100)
    }

    @Test("Query selector returns nil for missing element")
    func querySelectorReturnsNil() async throws {
        let mockConn = MockCDPConnection()
        await mockConn.setMockEvaluationResult("null")
        let session = CDPBrowserSession(connection: mockConn)

        let element = try await session.querySelector("#missing")

        #expect(element == nil)
    }

    @Test("Query selector all returns array of elements")
    func querySelectorAllReturnsArray() async throws {
        let mockConn = MockCDPConnection()
        let elementsJSON = """
        [{"tagName":"div","id":null,"className":"item","text":"Item 1","attributes":{},"boundingBox":{"x":0,"y":0,"width":100,"height":50},"isVisible":true}]
        """
        await mockConn.setMockEvaluationResult(elementsJSON)
        let session = CDPBrowserSession(connection: mockConn)

        let elements = try await session.querySelectorAll(".item")

        #expect(elements.count == 1)
        #expect(elements[0].tagName == "div")
    }
}

@Suite("CDPBrowserSession JavaScript Evaluation")
struct CDPSessionJSEvaluationTests {

    @Test("Evaluate sends Runtime.evaluate with expression")
    func evaluateSendsExpression() async throws {
        let mockConn = MockCDPConnection()
        await mockConn.setMockEvaluationResult("42")
        let session = CDPBrowserSession(connection: mockConn)

        let result = try await session.evaluate(javascript: "1 + 1")

        let commands = await mockConn.sentCommands
        let evalCmd = commands.first { $0.method == "Runtime.evaluate" }
        #expect(evalCmd?.params?["expression"]?.stringValue == "1 + 1")
        #expect(evalCmd?.params?["returnByValue"]?.boolValue == true)
    }

    @Test("Evaluate throws on JS exception")
    func evaluateThrowsOnException() async throws {
        let mockConn = MockCDPConnection()
        // Mock a response with exception details
        await mockConn.setMockResponse(
            method: "Runtime.evaluate",
            result: [
                "exceptionDetails": .object([
                    "text": .string("Uncaught ReferenceError: x is not defined")
                ])
            ]
        )
        let session = CDPBrowserSession(connection: mockConn)

        await #expect(throws: BrowserError.self) {
            _ = try await session.evaluate(javascript: "x + 1")
        }
    }

    @Test("Evaluate handles empty result")
    func evaluateHandlesEmptyResult() async throws {
        let mockConn = MockCDPConnection()
        await mockConn.setMockEvaluationResult("")
        let session = CDPBrowserSession(connection: mockConn)

        let result = try await session.evaluate(javascript: "void 0")

        #expect(result == "")
    }
}

@Suite("CDPBrowserSession Lifecycle")
struct CDPSessionLifecycleTests {

    @Test("Close sets isActive to false")
    func closeSetsInactive() async throws {
        let mockConn = MockCDPConnection()
        let session = CDPBrowserSession(connection: mockConn)

        #expect(await session.isActive == true)

        try await session.close()

        #expect(await session.isActive == false)
    }

    @Test("Close disconnects connection")
    func closeDisconnects() async throws {
        let mockConn = MockCDPConnection()
        let session = CDPBrowserSession(connection: mockConn)

        try await session.close()

        #expect(await mockConn.didDisconnect == true)
    }
}
