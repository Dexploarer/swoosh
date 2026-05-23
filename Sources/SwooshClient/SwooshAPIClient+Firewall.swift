// SwooshClient/SwooshAPIClient+Firewall.swift — 0.4A Firewall endpoint methods
//
// Wire methods for `GET /api/firewall/grants`, `POST /api/firewall/grants`,
// `DELETE /api/firewall/grants/{permission}`, and `POST /api/firewall/check`.
// The actual permission gate stays at `SwooshFirewallActor.require` on
// the server — the client only carries grant / deny intent.

import Foundation

extension SwooshAPIClient {
    public func firewallGrants() async throws -> FirewallResponse {
        let request = try makeRequest(method: "GET", path: "api/firewall/grants", body: nil)
        return try await execute(request, as: FirewallResponse.self)
    }

    public func updateFirewall(_ body: FirewallGrantRequest) async throws -> FirewallMutationResponse {
        let encoded = try encoder.encode(body)
        let request = try makeRequest(method: "POST", path: "api/firewall/grants", body: encoded)
        return try await execute(request, as: FirewallMutationResponse.self)
    }

    public func revokeFirewall(permission: String) async throws -> FirewallResponse {
        let encoded = try pathComponent(permission)
        let request = try makeRequest(method: "DELETE", path: "api/firewall/grants/\(encoded)", body: nil)
        return try await execute(request, as: FirewallResponse.self)
    }

    public func checkFirewall(_ body: FirewallCheckRequest) async throws -> FirewallCheckResponse {
        let encoded = try encoder.encode(body)
        let request = try makeRequest(method: "POST", path: "api/firewall/check", body: encoded)
        return try await execute(request, as: FirewallCheckResponse.self)
    }
}
