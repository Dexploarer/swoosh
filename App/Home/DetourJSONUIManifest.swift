// DetourJSONUIManifest.swift — safe JSON-to-UI component vocabulary (0.5A)

import Foundation

struct DetourJSONUISpec: Codable, Equatable {
    var root: String
    var elements: [String: DetourJSONUIElement]
}

struct DetourJSONUIElement: Codable, Equatable {
    var type: DetourJSONUIComponentKind
    var props: [String: DetourJSONUIValue]
    var children: [String]
}

enum DetourJSONUIValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case strings([String])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode([String].self) {
            self = .strings(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .strings(value):
            try container.encode(value)
        }
    }

    var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }
}

enum DetourJSONUIComponentKind: String, Codable, CaseIterable, Equatable {
    case shell = "surface.shell"
    case grid = "layout.grid"
    case integrationCard = "integration.card"
    case connectorHealth = "connector.health"
    case credentialScope = "credential.scopePicker"
    case setupDoctor = "setup.doctor"
    case providerPicker = "provider.modelPicker"
    case inboxThread = "inbox.thread"
    case walletPortfolio = "wallet.portfolio"
    case chainCard = "wallet.chainCard"
    case relationshipCard = "relationship.card"
    case mcpServer = "mcp.serverCard"
    case canvasNode = "canvas.node"
    case promptNode = "prompt.node"
    case ragSource = "rag.sourceCard"
    case mediaRender = "media.renderCard"
    case spatialOrb = "spatial.connectorOrb"
    case capabilityGraph = "spatial.capabilityGraph"
}

struct DetourJSONUIComponentDefinition: Identifiable, Equatable {
    var id: String { type.rawValue }
    var type: DetourJSONUIComponentKind
    var title: String
    var summary: String
    var props: [String]
    var actions: [String]
    var supports3D: Bool
}

enum DetourJSONUIManifest {
    static let components: [DetourJSONUIComponentDefinition] = [
        component(.shell, "Surface", "Groups streamed UI into one trusted card.", ["title", "subtitle"], []),
        component(.grid, "Grid", "Lays out generated cards with adaptive columns.", ["minimumWidth"], []),
        component(.integrationCard, "Integration", "Connect, test, or configure an app.", ["integrationID", "title", "status", "scope"], ["connect", "test", "scope"]),
        component(.connectorHealth, "Health", "Shows live connector status from daemon tools.", ["connectorID", "status", "account"], ["test", "doctor"]),
        component(.credentialScope, "Scope", "Chooses whether a saved account acts as me or agent.", ["credentialID", "owner", "scope"], ["scope", "remove"]),
        component(.setupDoctor, "Doctor", "Explains and fixes failed setup checks.", ["targetID", "reason"], ["open", "retry"]),
        component(.providerPicker, "Model", "Picks model provider and fallback policy.", ["providerID", "modelID"], ["select", "test"]),
        component(.inboxThread, "Thread", "Shows agent/user message routing.", ["threadID", "platform", "status"], ["open", "reply"]),
        component(.walletPortfolio, "Portfolio", "Summarizes wallet and chain positions.", ["walletID", "total", "chains"], ["refresh"]),
        component(.chainCard, "Chain", "Shows Solana, BNB, EVM, or Hyperliquid state.", ["chain", "status"], ["connect", "refresh"]),
        component(.relationshipCard, "Relationship", "Captures per-contact routing and tone.", ["personID", "platform", "role"], ["edit"]),
        component(.mcpServer, "MCP", "Registers and tests an MCP server.", ["serverID", "transport", "tools"], ["connect", "discover"]),
        component(.canvasNode, "Canvas node", "Places a workflow, model, or tool node on canvas.", ["nodeID", "kind", "status"], ["open", "run"]),
        component(.promptNode, "Prompt node", "Builds prompt templates and routing rules.", ["templateID", "status"], ["edit", "test"]),
        component(.ragSource, "Knowledge", "Adds a safe local knowledge source.", ["sourceID", "kind", "status"], ["index", "remove"]),
        component(.mediaRender, "Media", "Tracks an image, video, or ComfyUI render.", ["jobID", "status"], ["open", "retry"]),
        component(.spatialOrb, "3D connector", "Shows a connector as a spatial status object.", ["connectorID", "status"], ["select"], supports3D: true),
        component(.capabilityGraph, "3D graph", "Explains capability relationships without exposing secrets.", ["graphID", "groups"], ["select"], supports3D: true),
    ]

    static var promptRules: [String] {
        [
            "Emit only component types listed in the Detour manifest.",
            "Never include raw credentials, cookies, tokens, browser history, or unapproved memories.",
            "Use action names instead of code; Detour routes actions through setup, verify, and doctor paths.",
            "Prefer integration.card for connector setup and credential.scopePicker for ownership decisions.",
        ]
    }

    private static func component(
        _ type: DetourJSONUIComponentKind,
        _ title: String,
        _ summary: String,
        _ props: [String],
        _ actions: [String],
        supports3D: Bool = false
    ) -> DetourJSONUIComponentDefinition {
        DetourJSONUIComponentDefinition(
            type: type,
            title: title,
            summary: summary,
            props: props,
            actions: actions,
            supports3D: supports3D
        )
    }
}

struct DetourJSONUIPatch: Codable, Equatable {
    enum Operation: String, Codable {
        case add
        case remove
        case replace
    }

    var op: Operation
    var path: String
    var value: DetourJSONUIElement?
    var stringValue: String?

    static func root(_ id: String) -> DetourJSONUIPatch {
        DetourJSONUIPatch(op: .add, path: "/root", value: nil, stringValue: id)
    }

    static func element(_ id: String, _ element: DetourJSONUIElement) -> DetourJSONUIPatch {
        DetourJSONUIPatch(op: .add, path: "/elements/\(id)", value: element, stringValue: nil)
    }
}

extension DetourJSONUISpec {
    var streamPatches: [DetourJSONUIPatch] {
        [DetourJSONUIPatch.root(root)]
            + elements.keys.sorted().compactMap { id in
                elements[id].map { DetourJSONUIPatch.element(id, $0) }
            }
    }
}
