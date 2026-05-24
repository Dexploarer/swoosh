// SwooshDaemon/DaemonProbes.swift — 0.9S Idle + focus signal probes
//
// Mac-only signal sources for the scout autopilot scheduler.
// Returning nil on non-macOS / when no data is available is the
// agreed-upon "no signal" contract — the scheduler treats nil as
// "ignore" rather than "user is active right now".

import Foundation
#if canImport(IOKit) && os(macOS)
import CoreGraphics
#endif
#if canImport(Intents)
import Intents
#endif

@Sendable
func currentIdleSeconds() async -> TimeInterval? {
    #if canImport(IOKit) && os(macOS)
    // CGEventSource gives wall-clock idle time across all event types
    // without an entitlement. Returns Double.greatestFiniteMagnitude
    // when no events have happened — clamp to nil in that case.
    let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .init(rawValue: ~0)!)
    if seconds.isFinite, seconds >= 0 { return seconds }
    return nil
    #else
    return nil
    #endif
}

@Sendable
func currentFocusIdentifier() async -> String? {
    #if canImport(Intents)
    let focused = INFocusStatusCenter.default.focusStatus.isFocused ?? false
    return focused ? "active" : nil
    #else
    return nil
    #endif
}
