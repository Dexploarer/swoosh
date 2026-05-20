// Apps/SwooshiOS/ProviderLogo.swift — Bundled brand mark + monogram fallback
//
// Looks up a brand SVG in Assets.xcassets keyed by provider id. The SVGs
// are CC0-licensed marks sourced from simpleicons.org. Providers that
// aren't in the catalog fall back to a tinted monogram via InitialsTile.

import SwiftUI

struct ProviderLogo: View {
    let providerID: String
    let providerName: String
    var size: CGFloat = 36
    var cornerRadius: CGFloat = 10

    var body: some View {
        if let assetName, UIImage(named: assetName) != nil {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.white)
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.18)
            }
            .frame(width: size, height: size)
        } else {
            InitialsTile(
                text: initials,
                background: monogramBackground,
                foreground: .white,
                size: size,
                cornerRadius: cornerRadius
            )
        }
    }

    /// Maps each known provider id to its bundled imageset name. Returns
    /// nil for providers without a bundled SVG (they render the monogram).
    private var assetName: String? {
        switch providerID {
        case "openai":     return "OpenAI"
        case "openrouter": return "OpenRouter"
        case "anthropic":  return "Anthropic"
        case "google":     return "Google"
        default:           return nil
        }
    }

    private var initials: String {
        switch providerID {
        case "eliza-cloud":      return "EZ"
        case "local-openai":     return "LO"
        case "local-diagnostic": return "LD"
        default:
            let trimmed = providerName.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ").prefix(2)
            if parts.count == 2 {
                return String(parts.map { $0.first ?? Character(" ") })
            }
            return String(trimmed.prefix(2)).uppercased()
        }
    }

    private var monogramBackground: Color {
        switch providerID {
        case "openai":           return Color(red: 0.06, green: 0.06, blue: 0.06)
        case "eliza-cloud":      return Color(red: 0.18, green: 0.65, blue: 0.55)
        case "local-openai":     return Color(red: 0.32, green: 0.38, blue: 0.46)
        case "local-diagnostic": return Color(red: 0.42, green: 0.42, blue: 0.48)
        default:                 return Color(red: 0.30, green: 0.30, blue: 0.36)
        }
    }
}

/// Channel / connector logo: takes the daemon's ChatAdapterKind raw
/// value and returns the matching bundled mark when available. Used by
/// the (forthcoming) Channels surface in ConnectionsScreen and any tool
/// row that surfaces an adapter target. Adapters without a bundled SVG
/// fall back to a tinted monogram derived from the display name.
struct ChannelLogo: View {
    let kindRawValue: String
    let displayName: String
    var size: CGFloat = 36
    var cornerRadius: CGFloat = 10

    var body: some View {
        if let assetName, UIImage(named: assetName) != nil {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.white)
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.18)
            }
            .frame(width: size, height: size)
        } else {
            InitialsTile(
                text: initials,
                background: monogramBackground,
                foreground: .white,
                size: size,
                cornerRadius: cornerRadius
            )
        }
    }

    /// Maps a ChatAdapterKind raw value to its bundled imageset name.
    /// Mirrors `Sources/SwooshChatSDK/ChatAdapterCatalog.swift`. New
    /// adapters added there should be reflected here.
    private var assetName: String? {
        switch kindRawValue {
        case "slack":           return "Slack"
        case "teams":           return "Teams"
        case "discord":         return "Discord"
        case "telegram":        return "Telegram"
        case "github":          return "GitHub"
        case "linear":          return "Linear"
        case "whatsApp":        return "WhatsApp"
        case "messenger":       return "Messenger"
        case "beeperMatrix":    return "Matrix"
        case "photonIMessage":  return "iMessage"
        case "resendEmail":     return "Resend"
        case "webex":           return "Webex"
        case "mattermost":      return "Mattermost"
        case "googleChat":      return "GoogleChat"
        case "x", "twitter":    return "X"
        default:                return nil
        }
    }

    private var initials: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: " ").prefix(2)
        if parts.count == 2 {
            return String(parts.map { $0.first ?? Character(" ") })
        }
        return String(trimmed.prefix(2)).uppercased()
    }

    private var monogramBackground: Color {
        switch kindRawValue {
        case "slack":    return Color(red: 0.30, green: 0.07, blue: 0.30)
        case "teams":    return Color(red: 0.30, green: 0.32, blue: 0.66)
        case "messenger":return Color(red: 0.00, green: 0.45, blue: 1.00)
        case "memory",
             "swoosh",
             "web":      return Color(red: 0.30, green: 0.30, blue: 0.36)
        default:         return Color(red: 0.30, green: 0.30, blue: 0.36)
        }
    }
}

/// Chain logo: SVG-backed for Solana / Ethereum / BNB; monogram for Base
/// (Base isn't on simpleicons; their official mark would need to be
/// dropped into Assets.xcassets/Base.imageset by hand later).
struct ChainLogo: View {
    let chainRawValue: String
    let symbol: String
    let tintHex: String
    var size: CGFloat = 36
    var cornerRadius: CGFloat = 10

    var body: some View {
        if let assetName, UIImage(named: assetName) != nil {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.white)
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.18)
            }
            .frame(width: size, height: size)
        } else {
            InitialsTile(
                text: symbol,
                background: tintColor,
                foreground: .white,
                size: size,
                cornerRadius: cornerRadius
            )
        }
    }

    private var assetName: String? {
        switch chainRawValue {
        case "solana":   return "Solana"
        case "ethereum": return "Ethereum"
        case "bnb":      return "BNBChain"
        default:         return nil  // base → monogram
        }
    }

    private var tintColor: Color {
        var s = tintHex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return .accentColor }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}
