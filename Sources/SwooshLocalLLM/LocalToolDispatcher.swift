// SwooshLocalLLM/LocalToolDispatcher.swift — 0.9R On-device tool registry
//
// Wires `SwooshDispatchTool` to a tiny registry of read-only, side-effect-
// free iOS-local tools. The model running on-device can call these even
// when the Mac daemon is unreachable, but cannot reach any tool with side
// effects, network access, or wallet/secret access.
//
// Firewall invariant:
//   - macOS daemon side has the real `SwooshFirewall`. Any risky tool call
//     MUST round-trip there. When the daemon is reachable, an optional
//     `remoteDispatch` closure forwards calls to `/api/tools/execute`.
//   - When the daemon is unreachable (the fallback case), only the local
//     read-only tools answer. Risky names return an error, never silently
//     execute. The local registry deliberately contains zero tools that
//     mutate filesystem, network, wallet, or system state.
//
// Why the local set is firewall-exempt:
//   `clock_now` reads `Date()`. `device_info` reads `ProcessInfo` +
//   `UIDevice.current.model` (constant strings). `app_info` reads
//   `Bundle.main.infoDictionary`. None of them mutate state, read user
//   data, hit the network, or invoke other tools. Adding a fourth name
//   to `localToolNames` is a security decision — the runtime guard in
//   `dispatch` rejects any name not in this set so the registry can't
//   grow by accident. For visibility, every local call is reported to
//   the optional `localAudit` hook so the host can log it.
//
// Adding a tool here is a security decision — the gate is "would a
// malicious prompt running this tool harm the user?" If yes, do not add
// it; route it through the daemon instead.
//
// The dispatch logic itself is cross-platform so it can be tested on
// macOS via `swift test`. Only `install()` (which wires into the iOS-only
// `SwooshDispatchTool`) is gated to iOS.

import Foundation
import os
#if os(iOS) && canImport(UIKit)
import UIKit
#endif
#if os(iOS)
import LiteRTLM
#endif

public enum LocalToolDispatcher {

    public typealias RemoteDispatch = @Sendable (_ name: String, _ jsonArgs: String) async throws -> String
    public typealias LocalAudit = @Sendable (_ name: String, _ jsonArgs: String) -> Void

    /// Lock-protected slots for the dispatch hook and the audit hook. Both
    /// are written once by the client host and then read by every tool call,
    /// so `OSAllocatedUnfairLock` is the
    /// cheapest correctness-preserving primitive — it replaces the previous
    /// `nonisolated(unsafe) static var` slots, which had no synchronization
    /// and tripped Swift 6 strict-concurrency checks.
    private static let remoteDispatchSlot = OSAllocatedUnfairLock<RemoteDispatch?>(initialState: nil)
    private static let localAuditSlot = OSAllocatedUnfairLock<LocalAudit?>(initialState: nil)

    /// Set of tool names handled by the on-device safe registry. Exposed
    /// for tests and for callers that want to advertise them to the model.
    /// The runtime guard in `dispatch` rejects any other name, so this is
    /// a hard ceiling on the local attack surface.
    public static let localToolNames: Set<String> = ["clock_now", "device_info", "app_info"]

    /// Install the daemon-side forwarder for names outside `localToolNames`.
    /// Pass `nil` to clear (e.g. when the daemon disconnects). Safe to call
    /// from any actor.
    public static func setRemoteDispatch(_ handler: RemoteDispatch?) {
        remoteDispatchSlot.withLock { $0 = handler }
    }

    /// Install an audit hook called before every local tool execution. The
    /// host (iOS app) typically wires this to a log file or in-memory ring
    /// so the on-device call surface remains visible even when the daemon
    /// is unreachable. Safe to call from any actor.
    public static func setLocalAudit(_ hook: LocalAudit?) {
        localAuditSlot.withLock { $0 = hook }
    }

    #if os(iOS)
    /// Install this dispatcher as the global `SwooshDispatchTool` handler.
    /// Call once at app start, after the SwooshLocalLLM module is linked.
    public static func install() {
        SwooshDispatchTool.dispatch = { name, jsonArgs in
            try await dispatch(name: name, jsonArgs: jsonArgs)
        }
    }
    #endif

    /// Pure dispatch entry point. Cross-platform so unit tests on macOS
    /// can exercise the routing without an iOS host.
    public static func dispatch(name: String, jsonArgs: String) async throws -> String {
        // Local-set guard: only the three vetted names execute on-device.
        // Any other name MUST round-trip to the daemon (where the real
        // firewall lives) or be rejected.
        if localToolNames.contains(name) {
            localAuditSlot.withLock { $0 }?(name, jsonArgs)
            switch name {
            case "clock_now":
                return clockNow()
            case "device_info":
                return deviceInfo()
            case "app_info":
                return appInfo()
            default:
                // Unreachable: the contains check above gates this switch.
                // Fall through to the remote/error path so this stays a
                // total function even if `localToolNames` and the switch
                // ever drift.
                break
            }
        }
        if let remote = remoteDispatchSlot.withLock({ $0 }) {
            return try await remote(name, jsonArgs)
        }
        return encode(["error": "Tool '\(name)' is not available on-device. Mac daemon is unreachable."])
    }

    // MARK: - Local safe tools (read-only, no I/O beyond ProcessInfo)

    static func clockNow() -> String {
        let now = Date()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return encode([
            "iso8601": iso.string(from: now),
            "unix": Int(now.timeIntervalSince1970),
            "timezone": TimeZone.current.identifier,
        ])
    }

    static func deviceInfo() -> String {
        let info = ProcessInfo.processInfo
        var payload: [String: Any] = [
            "system_version": info.operatingSystemVersionString,
            "processor_count": info.activeProcessorCount,
            "physical_memory_bytes": info.physicalMemory,
            "available_memory_bytes": LiteRTDevicePolicy.availableMemoryBytes(),
        ]
        #if os(iOS) && canImport(UIKit)
        payload["platform"] = "iOS"
        payload["model"] = UIDevice.current.model
        payload["device_name"] = UIDevice.current.name
        #else
        payload["platform"] = "macOS"
        #endif
        return encode(payload)
    }

    static func appInfo() -> String {
        let bundle = Bundle.main
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let identifier = bundle.bundleIdentifier ?? "unknown"
        return encode([
            "identifier": identifier,
            "version": version,
            "build": build,
        ])
    }

    static func encode(_ payload: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let string = String(data: data, encoding: .utf8) else {
            return "{\"error\":\"Failed to encode tool response.\"}"
        }
        return string
    }
}
