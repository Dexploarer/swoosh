// SwooshCloudGaming/CloudGamingService.swift — Cloud gaming service registry
//
// Defines the supported cloud gaming platforms and their metadata.
// Web services embed via WKWebView; native services capture via ScreenCaptureKit.
// 0.5A – May 2026

import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - Web-based cloud gaming services
// ═══════════════════════════════════════════════════════════════════

/// Services that can be embedded in a WKWebView for browser-based streaming.
public enum CloudGamingService: String, CaseIterable, Codable, Sendable, Identifiable {
    case xboxCloud      // xbox.com/play — primary target
    case geforceNow     // play.geforcenow.com
    case amazonLuna     // luna.amazon.com
    case boosteroid     // boosteroid.com

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .xboxCloud:   "Xbox Cloud Gaming"
        case .geforceNow:  "GeForce NOW"
        case .amazonLuna:  "Amazon Luna"
        case .boosteroid:  "Boosteroid"
        }
    }

    public var streamURL: URL {
        switch self {
        case .xboxCloud:   URL(string: "https://xbox.com/play")!
        case .geforceNow:  URL(string: "https://play.geforcenow.com")!
        case .amazonLuna:  URL(string: "https://luna.amazon.com")!
        case .boosteroid:  URL(string: "https://boosteroid.com")!
        }
    }

    /// SF Symbol name for the service icon.
    public var iconName: String {
        switch self {
        case .xboxCloud:   "xbox.logo"
        case .geforceNow:  "bolt.fill"
        case .amazonLuna:  "moon.fill"
        case .boosteroid:  "flame.fill"
        }
    }

    /// Hex accent color for UI theming.
    public var accentHex: String {
        switch self {
        case .xboxCloud:   "#107C10"   // Xbox green
        case .geforceNow:  "#76B900"   // NVIDIA green
        case .amazonLuna:  "#FF9900"   // Amazon orange
        case .boosteroid:  "#6C5CE7"   // Boosteroid purple
        }
    }

    /// User-Agent override for WKWebView to ensure service compatibility.
    /// Some services check for a desktop browser UA to enable streaming.
    public var userAgentOverride: String? {
        switch self {
        case .xboxCloud:
            // Xbox Cloud Gaming requires a desktop Edge/Chrome UA
            return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36 Edg/125.0.0.0"
        case .geforceNow:
            return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"
        default:
            return nil
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Native game sources
// ═══════════════════════════════════════════════════════════════════

/// Sources that require native window capture via ScreenCaptureKit + CGEvent.
public enum NativeGameSource: String, CaseIterable, Codable, Sendable, Identifiable {
    case greenlight      // Greenlight (open-source Xbox streaming client)
    case steamLink       // Steam Link macOS app
    case playstation     // PS Plus PC app
    case localWindow     // Any arbitrary macOS window

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .greenlight:   "Greenlight (Xbox)"
        case .steamLink:    "Steam Link"
        case .playstation:  "PlayStation Plus"
        case .localWindow:  "Local Window"
        }
    }

    public var iconName: String {
        switch self {
        case .greenlight:   "xbox.logo"
        case .steamLink:    "gamecontroller.fill"
        case .playstation:  "playstation.logo"
        case .localWindow:  "desktopcomputer"
        }
    }

    /// Bundle identifier patterns to auto-detect running instances.
    public var bundleIdentifiers: [String] {
        switch self {
        case .greenlight:   ["com.electron.greenlight", "nl.nicovs.greenlight"]
        case .steamLink:    ["com.valvesoftware.steamlink", "com.valvesoftware.SteamLink", "com.valvesoftware.SteamLink17"]
        case .playstation:  [
            "com.playstation.RemotePlay",      // Official PS Remote Play
            "com.playstation.psremoteplay",     // Alt casing
            "re.chiaki.chiaki",                 // Chiaki (open-source PS Remote Play)
            "re.chiaki.chiaki4deck",            // Chiaki4deck variant
            "com.playstation.psplus",           // PS Plus PC app
        ]
        case .localWindow:  []
        }
    }

    /// Human-readable setup instructions.
    public var setupInstructions: String {
        switch self {
        case .greenlight:
            "Install Greenlight from GitHub and sign into your Xbox account."
        case .steamLink:
            "Install Steam Link from the Mac App Store and pair with your PC."
        case .playstation:
            """
            Option A: Install PS Remote Play from playstation.com/remote-play \
            and sign into your PSN account.
            Option B: Install Chiaki (open-source, lower latency) via \
            'brew install --cask chiaki' and register your PS5.
            """
        case .localWindow:
            "Select any macOS window to capture."
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Unified source
// ═══════════════════════════════════════════════════════════════════

/// A unified source that can be either web-based or native.
public enum GameSource: Codable, Sendable, Hashable {
    case web(CloudGamingService)
    case native(NativeGameSource)

    public var displayName: String {
        switch self {
        case .web(let svc):    svc.displayName
        case .native(let src): src.displayName
        }
    }

    public var iconName: String {
        switch self {
        case .web(let svc):    svc.iconName
        case .native(let src): src.iconName
        }
    }
}
