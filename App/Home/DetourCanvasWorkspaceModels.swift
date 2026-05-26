// DetourCanvasWorkspaceModels.swift — trusted canvas workspace projection (0.5A)

import Foundation

enum DetourHomeWorkspaceMode {
    case commandCenter
    case canvas
}

enum DetourHomeFocus: String, CaseIterable, Identifiable {
    case overview
    case apps
    case social
    case inbox
    case wallet
    case setup
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Now"
        case .apps: "Apps"
        case .social: "Social"
        case .inbox: "Inbox"
        case .wallet: "Wallets"
        case .setup: "Context"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "sparkles"
        case .apps: "square.grid.2x2"
        case .social: "bubble.left.and.bubble.right"
        case .inbox: "tray.full"
        case .wallet: "wallet.pass"
        case .setup: "tree"
        case .settings: "gearshape"
        }
    }

    static func infer(from text: String) -> DetourHomeFocus {
        let command = text.lowercased()
        if command.contains("discord") || command.contains("telegram") || command.contains("x ") || command.contains("social") {
            return .social
        }
        if command.contains("app") || command.contains("connector") || command.contains("integration") || command.contains("connect") {
            return .apps
        }
        if command.contains("inbox") || command.contains("message") || command.contains("reply") || command.contains("approval") {
            return .inbox
        }
        if command.contains("wallet") || command.contains("solana") || command.contains("hyperliquid") || command.contains("bsc") {
            return .wallet
        }
        if command.contains("settings") || command.contains("config") || command.contains("configure") {
            return .settings
        }
        if command.contains("setup") || command.contains("credential") || command.contains("permission") ||
            command.contains("memory") || command.contains("context") || command.contains("vault") {
            return .setup
        }
        return .overview
    }
}

enum DetourCanvasKind: String, CaseIterable, Identifiable {
    case media
    case workflow
    case prompt
    case models
    case knowledge
    case portfolio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .media: "Media"
        case .workflow: "Workflow"
        case .prompt: "Prompt"
        case .models: "Models"
        case .knowledge: "Knowledge"
        case .portfolio: "Portfolio"
        }
    }

    static func infer(from text: String) -> DetourCanvasKind {
        let command = text.lowercased()
        if command.contains("comfy") || command.contains("media") || command.contains("image") || command.contains("video") {
            return .media
        }
        if command.contains("prompt") || command.contains("character") || command.contains("template") {
            return .prompt
        }
        if command.contains("model") || command.contains("mlx") || command.contains("local") || command.contains("route") {
            return .models
        }
        if command.contains("rag") || command.contains("knowledge") || command.contains("memory") {
            return .knowledge
        }
        if command.contains("wallet") || command.contains("solana") || command.contains("hyperliquid") || command.contains("bsc") {
            return .portfolio
        }
        return .workflow
    }
}

struct DetourCanvasWorkspace {
    var title: String
    var subtitle: String
    var request: String
    var nodes: [DetourCanvasNode]
    var edges: [DetourCanvasEdge]
    var artifacts: [DetourCanvasArtifact]
}

struct DetourCanvasNode: Identifiable, Equatable {
    var id: String
    var title: String
    var subtitle: String
    var systemImage: String
    var tone: DetourGeneratedTone
    var status: DetourCanvasStatus
}

struct DetourCanvasEdge: Identifiable, Equatable {
    var id: String { "\(from)-\(to)" }
    var from: String
    var to: String
}

enum DetourCanvasStatus: String {
    case ready = "Ready"
    case live = "Live"
    case pending = "Pending"
    case needsSetup = "Needs setup"
    case offline = "Offline"
}
