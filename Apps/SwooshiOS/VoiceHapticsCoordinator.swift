// Apps/SwooshiOS/VoiceHapticsCoordinator.swift — 0.9R Voice-synced haptics
//
// Drives a continuous CHHapticEngine pattern whose intensity and
// sharpness follow the live audio level (mic input during listening,
// TTS playback level otherwise). The result: the liquid sphere doesn't
// just *look* alive — you feel it pulse in your palm.
//
// Uses the long-lived "continuous" event style with `sendParameters`
// to modulate intensity at ~30 Hz. Falls back to silent no-op on
// devices without CoreHaptics (iPad without Taptic Engine, etc.).

import Foundation
#if canImport(CoreHaptics)
import CoreHaptics
#endif

@MainActor
final class VoiceHapticsCoordinator {

    static let shared = VoiceHapticsCoordinator()

    #if canImport(CoreHaptics)
    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?
    private var refreshTimer: DispatchSourceTimer?
    private var isSupported: Bool { CHHapticEngine.capabilitiesForHardware().supportsHaptics }
    #else
    private var isSupported: Bool { false }
    #endif

    private var running: Bool = false

    /// CHHapticPattern duration — must match the timer cadence below.
    private static let patternDurationSeconds: TimeInterval = 30

    /// Stand up the engine + start the continuous pattern. Safe to call
    /// repeatedly — no-op if already running or unsupported. Audio level
    /// updates flow through `update(level:)`.
    func start() {
        guard !running, isSupported else { return }
        #if canImport(CoreHaptics)
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = true
            try engine.start()
            self.engine = engine

            // Continuous event; auto-restarts via the refresh timer below
            // so voice sessions longer than `patternDurationSeconds`
            // continue to react to live audio level.
            let player = try Self.buildPlayer(engine: engine)
            try player.start(atTime: 0)
            self.player = player
            running = true
            scheduleRefresh()
        } catch {
            // Silent fail — haptics are decorative, not load-bearing.
            running = false
        }
        #endif
    }

    /// Stop the continuous event and release the engine. Idempotent.
    func stop() {
        guard running else { return }
        #if canImport(CoreHaptics)
        refreshTimer?.cancel()
        refreshTimer = nil
        try? player?.stop(atTime: 0)
        player = nil
        engine?.stop()
        engine = nil
        #endif
        running = false
    }

    #if canImport(CoreHaptics)
    /// Build the canonical continuous-event pattern player. Called from
    /// `start()` and from the refresh timer so the player resets just
    /// before the pattern expires.
    private static func buildPlayer(engine: CHHapticEngine) throws -> CHHapticAdvancedPatternPlayer {
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.0)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [intensity, sharpness],
            relativeTime: 0,
            duration: patternDurationSeconds
        )
        let pattern = try CHHapticPattern(events: [event], parameters: [])
        return try engine.makeAdvancedPlayer(with: pattern)
    }

    /// Re-arm the continuous event ~2 s before it expires so live
    /// `update(level:)` calls never silently stop modulating.
    private func scheduleRefresh() {
        refreshTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        let interval = Self.patternDurationSeconds - 2
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self, let engine = self.engine else { return }
            do {
                try? self.player?.stop(atTime: 0)
                let player = try Self.buildPlayer(engine: engine)
                try player.start(atTime: 0)
                self.player = player
            } catch {
                // Decorative; keep silent.
            }
        }
        timer.resume()
        refreshTimer = timer
    }
    #endif

    /// Modulate the live pattern with a fresh audio level in [0, 1].
    /// Call at ~30 Hz from the audio source. Out-of-range values are
    /// clamped; intensity below 0.05 still plays a faint pulse so the
    /// haptic doesn't drop out entirely between syllables.
    func update(level: Float) {
        guard running else { return }
        #if canImport(CoreHaptics)
        let clamped = max(0.0, min(1.0, level))
        let intensityValue = max(0.05, clamped)
        let sharpnessValue = 0.3 + clamped * 0.7  // 0.3..1.0 — brighter at peaks
        let params: [CHHapticDynamicParameter] = [
            .init(parameterID: .hapticIntensityControl, value: intensityValue, relativeTime: 0),
            .init(parameterID: .hapticSharpnessControl, value: sharpnessValue, relativeTime: 0),
        ]
        try? player?.sendParameters(params, atTime: 0)
        #endif
    }
}
