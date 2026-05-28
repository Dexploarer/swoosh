// SwooshToolsets/GamingNavigation/GamingNavigationTools.swift — 0.9U Gaming navigation tools
//
// Six tools for voice-driven game navigation in the cloud gaming WKWebView:
//   gaming_search_game      — search for a game by name
//   gaming_click_element    — click a CSS selector in the web view
//   gaming_type_text        — type text into the focused element
//   gaming_navigate_url     — navigate the web view to a URL
//   gaming_screenshot_web   — capture current web view state
//   gaming_select_platform  — switch cloud gaming platform
//
// All tools communicate with the UI layer via NotificationCenter since
// WKWebView lives in the main-actor UI layer.

#if os(macOS)

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - gaming_search_game
// ═══════════════════════════════════════════════════════════════════

public struct GamingSearchGameTool: SwooshTool {
    public struct Input: Codable, Sendable {
        public let query: String
    }

    public struct Output: Codable, Sendable {
        public let success: Bool
        public let message: String
    }

    public static let name: ToolName = "gaming_search_game"
    public static let displayName = "Search Game"
    public static let description = "Search for a game by name on the current cloud gaming platform."
    public static let permission = SwooshPermission.nitrogenControl
    public static let risk = ToolRisk.medium
    public static let approval = ApprovalPolicy.askFirstTime
    public static let toolset = ToolsetID.nitrogen
    public static let platforms: Set<ToolPlatform> = [.macOS]

    public typealias InputType = Input
    public typealias OutputType = Output

    public init() {}

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .swooshGamingSearchGame,
                object: nil,
                userInfo: ["query": input.query]
            )
        }
        return Output(
            success: true,
            message: "Search request sent for '\(input.query)'."
        )
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - gaming_click_element
// ═══════════════════════════════════════════════════════════════════

public struct GamingClickElementTool: SwooshTool {
    public struct Input: Codable, Sendable {
        public let selector: String
    }

    public struct Output: Codable, Sendable {
        public let success: Bool
        public let message: String
    }

    public static let name: ToolName = "gaming_click_element"
    public static let displayName = "Click Element"
    public static let description = "Click a CSS selector element in the embedded cloud gaming web view."
    public static let permission = SwooshPermission.nitrogenControl
    public static let risk = ToolRisk.medium
    public static let approval = ApprovalPolicy.askFirstTime
    public static let toolset = ToolsetID.nitrogen
    public static let platforms: Set<ToolPlatform> = [.macOS]

    public typealias InputType = Input
    public typealias OutputType = Output

    public init() {}

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .swooshGamingClickElement,
                object: nil,
                userInfo: ["selector": input.selector]
            )
        }
        return Output(
            success: true,
            message: "Click request sent for selector '\(input.selector)'."
        )
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - gaming_type_text
// ═══════════════════════════════════════════════════════════════════

public struct GamingTypeTextTool: SwooshTool {
    public struct Input: Codable, Sendable {
        public let text: String
    }

    public struct Output: Codable, Sendable {
        public let success: Bool
        public let message: String
    }

    public static let name: ToolName = "gaming_type_text"
    public static let displayName = "Type Text"
    public static let description = "Type text into the focused element in the cloud gaming web view."
    public static let permission = SwooshPermission.nitrogenControl
    public static let risk = ToolRisk.medium
    public static let approval = ApprovalPolicy.askFirstTime
    public static let toolset = ToolsetID.nitrogen
    public static let platforms: Set<ToolPlatform> = [.macOS]

    public typealias InputType = Input
    public typealias OutputType = Output

    public init() {}

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .swooshGamingTypeText,
                object: nil,
                userInfo: ["text": input.text]
            )
        }
        return Output(
            success: true,
            message: "Type request sent for text '\(input.text)'."
        )
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - gaming_navigate_url
// ═══════════════════════════════════════════════════════════════════

public struct GamingNavigateURLTool: SwooshTool {
    public struct Input: Codable, Sendable {
        public let url: String
    }

    public struct Output: Codable, Sendable {
        public let success: Bool
        public let message: String
    }

    public static let name: ToolName = "gaming_navigate_url"
    public static let displayName = "Navigate URL"
    public static let description = "Navigate the embedded cloud gaming web view to a specific URL."
    public static let permission = SwooshPermission.nitrogenControl
    public static let risk = ToolRisk.medium
    public static let approval = ApprovalPolicy.askFirstTime
    public static let toolset = ToolsetID.nitrogen
    public static let platforms: Set<ToolPlatform> = [.macOS]

    public typealias InputType = Input
    public typealias OutputType = Output

    public init() {}

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .swooshGamingNavigateURL,
                object: nil,
                userInfo: ["url": input.url]
            )
        }
        return Output(
            success: true,
            message: "Navigation request sent for URL '\(input.url)'."
        )
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - gaming_screenshot_web
// ═══════════════════════════════════════════════════════════════════

public struct GamingScreenshotWebTool: SwooshTool {
    public struct Input: Codable, Sendable {}

    public struct Output: Codable, Sendable {
        public let pageTitle: String
        public let pageURL: String
        public let hasVideo: Bool
        public let message: String
    }

    public static let name: ToolName = "gaming_screenshot_web"
    public static let displayName = "Screenshot Web View"
    public static let description = "Capture the current state of the cloud gaming web view as a description."
    public static let permission = SwooshPermission.nitrogenRead
    public static let risk = ToolRisk.low
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.nitrogen
    public static let platforms: Set<ToolPlatform> = [.macOS]

    public typealias InputType = Input
    public typealias OutputType = Output

    public init() {}

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .swooshGamingScreenshotWeb,
                object: nil,
                userInfo: [:]
            )
        }
        // TODO: Wire async reply from UI layer via a continuation or
        // response notification to populate real page metadata.
        return Output(
            pageTitle: "",
            pageURL: "",
            hasVideo: false,
            message: "Screenshot request sent to cloud gaming web view."
        )
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - gaming_select_platform
// ═══════════════════════════════════════════════════════════════════

public struct GamingSelectPlatformTool: SwooshTool {
    public struct Input: Codable, Sendable {
        /// One of: "xbox", "geforce", "luna", "boosteroid",
        /// "steamlink", "playstation", "greenlight".
        public let platform: String
    }

    public struct Output: Codable, Sendable {
        public let success: Bool
        public let selectedPlatform: String
        public let message: String
    }

    public static let name: ToolName = "gaming_select_platform"
    public static let displayName = "Select Platform"
    public static let description = "Switch the gaming pane to a specific cloud gaming platform or native source."
    public static let permission = SwooshPermission.nitrogenControl
    public static let risk = ToolRisk.medium
    public static let approval = ApprovalPolicy.askFirstTime
    public static let toolset = ToolsetID.nitrogen
    public static let platforms: Set<ToolPlatform> = [.macOS]

    public typealias InputType = Input
    public typealias OutputType = Output

    public init() {}

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .swooshGamingSelectPlatform,
                object: nil,
                userInfo: ["platform": input.platform]
            )
        }
        return Output(
            success: true,
            selectedPlatform: input.platform,
            message: "Platform switch request sent for '\(input.platform)'."
        )
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Notification names
// ═══════════════════════════════════════════════════════════════════

public extension Notification.Name {
    static let swooshGamingSearchGame = Notification.Name("ai.swoosh.gaming.searchGame")
    static let swooshGamingClickElement = Notification.Name("ai.swoosh.gaming.clickElement")
    static let swooshGamingTypeText = Notification.Name("ai.swoosh.gaming.typeText")
    static let swooshGamingNavigateURL = Notification.Name("ai.swoosh.gaming.navigateURL")
    static let swooshGamingScreenshotWeb = Notification.Name("ai.swoosh.gaming.screenshotWeb")
    static let swooshGamingSelectPlatform = Notification.Name("ai.swoosh.gaming.selectPlatform")
}

#endif
