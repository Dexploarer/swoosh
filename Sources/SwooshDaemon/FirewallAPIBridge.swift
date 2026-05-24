// SwooshDaemon/FirewallAPIBridge.swift — 0.9S Firewall ↔ HTTP API
//
// Exposes `SwooshFirewallActor` over HTTP for grant / revoke /
// check / list. The same actor every tool call routes through — no
// shadow copy, no parallel decision plane. This is purposely the only
// path that mutates firewall state from outside the agent loop.

import Foundation
import SwooshAPI
import SwooshClient
import SwooshFirewall
import SwooshTools

extension SwooshDaemon {

    static func firewallResponse(firewall: SwooshFirewallActor) async -> FirewallResponse {
        let granted = await firewall.listGranted()
        let denied = await firewall.listDenied()
        return FirewallResponse(
            granted: granted.map(\.rawValue).sorted(),
            denied: denied.map(\.rawValue).sorted()
        )
    }

    static func updateFirewallResponse(
        firewall: SwooshFirewallActor,
        request: FirewallGrantRequest
    ) async throws -> FirewallMutationResponse {
        guard let permission = SwooshPermission(rawValue: request.permission) else {
            throw APIError.badRequest("unknown permission: \(request.permission)")
        }
        let trimmedDecision = request.decision.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let message: String
        switch trimmedDecision {
        case "grant", "allow":
            await firewall.grant(permission)
            message = "Granted \(permission.rawValue)."
        case "deny", "block":
            await firewall.deny(permission)
            message = "Denied \(permission.rawValue)."
        default:
            throw APIError.badRequest("unknown decision: \(request.decision) (use \"grant\" or \"deny\")")
        }
        let fw = await firewallResponse(firewall: firewall)
        return FirewallMutationResponse(firewall: fw, message: message)
    }

    static func revokeFirewallResponse(
        firewall: SwooshFirewallActor,
        permission: String
    ) async throws -> FirewallResponse {
        guard let perm = SwooshPermission(rawValue: permission) else {
            throw APIError.badRequest("unknown permission: \(permission)")
        }
        await firewall.revoke(perm)
        return await firewallResponse(firewall: firewall)
    }

    static func checkFirewallResponse(
        firewall: SwooshFirewallActor,
        request: FirewallCheckRequest
    ) async throws -> FirewallCheckResponse {
        guard let perm = SwooshPermission(rawValue: request.permission) else {
            throw APIError.badRequest("unknown permission: \(request.permission)")
        }
        let granted = await firewall.isGranted(perm)
        let denied = await firewall.listDenied().contains(perm)
        return FirewallCheckResponse(
            permission: perm.rawValue,
            granted: granted,
            denied: denied
        )
    }
}
