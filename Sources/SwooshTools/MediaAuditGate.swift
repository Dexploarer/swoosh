// SwooshTools/MediaAuditGate.swift — 0.4A Media-provider audit + firewall gate
//
// Shared helper for media-generation providers (image, video, 3D, music).
// Each provider holds one `MediaAuditGate` and calls `start`/`succeeded`/
// `failed`/`denied` instead of inlining the same firewall+audit plumbing.
// The registry-mounted tool wrappers are the primary permission gate;
// this helper is the defense-in-depth path for direct (non-registry)
// callers (e.g. iOS picker, daemon admin paths).
//
// `promptDigest` returns a deterministic short hash suitable for audit
// detail — Swift's per-process-random `String.hash` would break audit
// correlation across daemon restarts.

import Foundation
import CryptoKit

public struct MediaAuditGate: Sendable {
    public let toolName: String
    public let permission: SwooshPermission
    private let firewall: (any Firewall)?
    private let auditLog: (any AuditLogging)?

    public init(
        toolName: String,
        permission: SwooshPermission,
        firewall: (any Firewall)? = nil,
        auditLog: (any AuditLogging)? = nil
    ) {
        self.toolName = toolName
        self.permission = permission
        self.firewall = firewall
        self.auditLog = auditLog
    }

    /// Throw if the configured firewall denies `permission`. No-op when
    /// no firewall is injected (picker path).
    public func requirePermission() async throws {
        guard let firewall else { return }
        do {
            try await firewall.require(permission)
        } catch {
            await emit(.toolCallDenied, "denied", success: false)
            throw error
        }
    }

    public func started(_ detail: String) async {
        await emit(.toolCallStarted, detail)
    }

    public func succeeded(_ detail: String) async {
        await emit(.toolCallSucceeded, detail)
    }

    public func failed(_ detail: String) async {
        await emit(.toolCallFailed, detail, success: false)
    }

    private func emit(_ kind: AuditEntryKind, _ detail: String, success: Bool = true) async {
        guard let auditLog else { return }
        try? await auditLog.append(AuditEntry(
            kind: kind, toolName: toolName, detail: detail, success: success
        ))
    }

    /// Deterministic 16-hex-char digest of a prompt. Used in audit
    /// `detail` so reviewers can correlate runs across daemon restarts
    /// without exposing the prompt text itself. Truncated SHA-256.
    public static func promptDigest(_ prompt: String) -> String {
        let data = Data(prompt.utf8)
        let digest = SHA256.hash(data: data)
        let bytes = Array(digest).prefix(8)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
