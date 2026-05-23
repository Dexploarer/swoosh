// SwooshClient/WireTypes+Firewall.swift — 0.4A Tier 1 Firewall wire types
//
// Wire format for `GET/POST /api/firewall/grants`,
// `DELETE /api/firewall/grants/{permission}`, and the
// `POST /api/firewall/check` query. The actual permission gate stays at
// `SwooshFirewallActor.require` on the server — the wire only carries
// names and decision strings.

import Foundation

public struct FirewallResponse: Codable, Sendable, Equatable {
    public let granted: [String]
    public let denied: [String]

    public init(granted: [String], denied: [String]) {
        self.granted = granted
        self.denied = denied
    }
}

public struct FirewallGrantRequest: Codable, Sendable, Equatable {
    public let permission: String
    public let decision: String   // "grant" | "deny"

    public init(permission: String, decision: String = "grant") {
        self.permission = permission
        self.decision = decision
    }
}

public struct FirewallMutationResponse: Codable, Sendable, Equatable {
    public let firewall: FirewallResponse
    public let message: String

    public init(firewall: FirewallResponse, message: String) {
        self.firewall = firewall
        self.message = message
    }
}

public struct FirewallCheckRequest: Codable, Sendable, Equatable {
    public let permission: String

    public init(permission: String) {
        self.permission = permission
    }
}

public struct FirewallCheckResponse: Codable, Sendable, Equatable {
    public let permission: String
    public let granted: Bool
    public let denied: Bool

    public init(permission: String, granted: Bool, denied: Bool) {
        self.permission = permission
        self.granted = granted
        self.denied = denied
    }
}
