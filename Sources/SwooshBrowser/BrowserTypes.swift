// SwooshBrowser/BrowserTypes.swift — Browser automation types
//
// Hermes-inspired browser automation via Chrome DevTools Protocol (CDP).
// Supports navigation, clicking, typing, screenshotting, text extraction,
// and vision-based page analysis.

import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - Browser session protocol
// ═══════════════════════════════════════════════════════════════════

/// A browser session for automated page interaction.
public protocol BrowserSession: Sendable {
    var sessionID: String { get }
    var currentURL: URL? { get async }
    var isActive: Bool { get async }

    // Navigation
    func navigate(to url: URL) async throws
    func goBack() async throws
    func goForward() async throws
    func reload() async throws
    func waitForLoad(timeout: TimeInterval) async throws

    // Interaction
    func click(selector: String) async throws
    func type(selector: String, text: String) async throws
    func clear(selector: String) async throws
    func select(selector: String, value: String) async throws
    func scroll(x: Int, y: Int) async throws
    func hover(selector: String) async throws

    // Extraction
    func screenshot(fullPage: Bool) async throws -> Data
    func extractText() async throws -> String
    func extractHTML() async throws -> String
    func extractLinks() async throws -> [PageLink]
    func extractForms() async throws -> [PageForm]
    func querySelector(_ selector: String) async throws -> ElementInfo?
    func querySelectorAll(_ selector: String) async throws -> [ElementInfo]

    // JavaScript
    func evaluate(javascript: String) async throws -> String

    // Lifecycle
    func close() async throws
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Page element types
// ═══════════════════════════════════════════════════════════════════

/// A link found on a page.
public struct PageLink: Codable, Sendable, Identifiable {
    public let id: String
    public let href: String
    public let text: String
    public let isExternal: Bool

    public init(href: String, text: String, isExternal: Bool = false) {
        self.id = UUID().uuidString
        self.href = href
        self.text = text
        self.isExternal = isExternal
    }
}

/// A form found on a page.
public struct PageForm: Codable, Sendable, Identifiable {
    public let id: String
    public let action: String?
    public let method: String
    public let fields: [FormField]

    public init(action: String?, method: String = "GET", fields: [FormField] = []) {
        self.id = UUID().uuidString
        self.action = action
        self.method = method
        self.fields = fields
    }
}

/// A form field.
public struct FormField: Codable, Sendable {
    public let name: String
    public let type: String        // text, password, email, etc.
    public let value: String?
    public let placeholder: String?
    public let required: Bool

    public init(name: String, type: String = "text", value: String? = nil,
                placeholder: String? = nil, required: Bool = false) {
        self.name = name
        self.type = type
        self.value = value
        self.placeholder = placeholder
        self.required = required
    }
}

/// Information about a DOM element.
public struct ElementInfo: Codable, Sendable {
    public let tagName: String
    public let id: String?
    public let className: String?
    public let text: String
    public let attributes: [String: String]
    public let boundingBox: BoundingBox?
    public let isVisible: Bool

    public init(tagName: String, id: String? = nil, className: String? = nil,
                text: String = "", attributes: [String: String] = [:],
                boundingBox: BoundingBox? = nil, isVisible: Bool = true) {
        self.tagName = tagName
        self.id = id
        self.className = className
        self.text = text
        self.attributes = attributes
        self.boundingBox = boundingBox
        self.isVisible = isVisible
    }
}

/// Bounding box of an element on the page.
public struct BoundingBox: Codable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Browser errors
// ═══════════════════════════════════════════════════════════════════

public enum BrowserError: Error, Sendable {
    case connectionFailed(String)
    case navigationFailed(URL, String)
    case elementNotFound(String)
    case evaluationFailed(String)
    case screenshotFailed(String)
    case timeout(String)
    case sessionClosed
    case chromeNotFound
    case cdpProtocolError(Int, String)
    case invalidAction(String)
}
