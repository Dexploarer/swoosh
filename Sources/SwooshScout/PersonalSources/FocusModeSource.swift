// SwooshScout/PersonalSources/FocusModeSource.swift — 0.9S Focus mode snapshot
//
// Reports whether the user is currently in Do Not Disturb, Work focus,
// Personal, etc. via `INFocusStatusCenter` (Intents framework). One
// record per scan describing the current focus state; the candidate
// generator builds a "user typically works during focus mode" memory
// over multiple scans.

import Foundation
#if canImport(Intents)
import Intents
#endif

public struct FocusModeSource: ScoutSource {
    public let id = "focus_mode"
    public let displayName = "Focus Mode"
    public let description = "Whether the user is in Do Not Disturb, Work focus, etc."
    public let sensitivity = Sensitivity.medium
    public let requiredPermissions = ["focus_mode.read"]

    public init() {}

    public func checkPermission() async throws -> SourcePermissionStatus {
        #if canImport(Intents)
        switch INFocusStatusCenter.default.authorizationStatus {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
        #else
        return .denied
        #endif
    }

    public func requestPermission() async throws -> SourcePermissionStatus {
        #if canImport(Intents)
        let status = await withCheckedContinuation { continuation in
            INFocusStatusCenter.default.requestAuthorization { result in
                continuation.resume(returning: result)
            }
        }
        switch status {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
        #else
        return .denied
        #endif
    }

    public func scan(progress: ScanProgress) async throws -> [ScoutRecord] {
        #if canImport(Intents)
        let status = INFocusStatusCenter.default.focusStatus
        let isFocused = status.isFocused ?? false
        return [
            ScoutRecord(
                sourceID: id, kind: .focusMode, sensitivity: .medium,
                content: isFocused ? "Focus mode is currently active" : "No focus mode active",
                metadata: ["isFocused": String(isFocused)]
            )
        ]
        #else
        return []
        #endif
    }
}
