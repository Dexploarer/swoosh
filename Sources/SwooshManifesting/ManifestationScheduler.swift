// SwooshManifesting/ManifestationScheduler.swift — When to manifest
//
// Hermes runs its Curator on a 7-day cron. Apple platforms give us a
// richer trigger surface: time-of-day, system-idle, focus mode, AC
// power, calendar quiet hours. This file is the policy seam — the
// daemon hands a configured `ManifestationScheduler` a `Manifester`
// and a `triggers` actor and the scheduler decides when to fire.
//
// The policy types and the `tick()` entry point are already here so the
// daemon's main loop can call them on whatever cadence we want.

import Foundation

/// When the manifester should fire.
public struct ManifestationPolicy: Sendable, Codable {
    /// Soonest allowed gap between two successful passes. A "daily floor"
    /// of 24h matches Hermes's once-a-day rhythm; raising it to 7d
    /// matches their default. Default: 24h.
    public var minimumInterval: TimeInterval
    /// Idle-time threshold. If the system has been idle for at least
    /// this long (and no manifestation has run inside `minimumInterval`),
    /// fire one. The Mac daemon plugs `IOPMAssertion` idle queries into
    /// this check; on platforms without idle detection it stays nil.
    public var idleThreshold: TimeInterval?
    /// Skip manifesting while these focus modes are active. The string
    /// values are matched against the Focus identifiers SwooshFocus
    /// surfaces.
    public var skipDuringFocus: Set<String>
    /// Hard upper bound — even if everything else aligns, never fire
    /// more often than this. Default: 1 hour.
    public var minimumCooldown: TimeInterval

    public init(
        minimumInterval: TimeInterval = 60 * 60 * 24,        // 1 day
        idleThreshold: TimeInterval? = 30 * 60,              // 30 min
        skipDuringFocus: Set<String> = ["com.apple.donotdisturb.mode.work"],
        minimumCooldown: TimeInterval = 60 * 60              // 1 hour
    ) {
        self.minimumInterval = minimumInterval
        self.idleThreshold = idleThreshold
        self.skipDuringFocus = skipDuringFocus
        self.minimumCooldown = minimumCooldown
    }
}

/// Decide-and-fire policy wrapper. Holds a `Manifester` and a policy and
/// answers "should I run right now?" given the current world state.
/// Callers poll `tick(now:idleSeconds:activeFocus:)`.
public actor ManifestationScheduler {
    public let policy: ManifestationPolicy
    private let manifester: Manifester
    private let store: any ManifestationStoring

    public init(
        manifester: Manifester,
        store: any ManifestationStoring,
        policy: ManifestationPolicy = ManifestationPolicy()
    ) {
        self.manifester = manifester
        self.store = store
        self.policy = policy
    }

    /// Evaluate the policy and run a manifestation pass if conditions
    /// are met. Caller supplies the ambient world state — keeps this
    /// module testable without time/idle/Focus side effects.
    @discardableResult
    public func tick(
        now: Date = Date(),
        idleSeconds: TimeInterval? = nil,
        activeFocus: String? = nil
    ) async throws -> Manifestation? {
        if let focus = activeFocus, policy.skipDuringFocus.contains(focus) {
            return nil
        }
        let last = try await store.mostRecentCompleted()
        let elapsed = last.flatMap { $0.finishedAt }.map { now.timeIntervalSince($0) } ?? .greatestFiniteMagnitude

        if elapsed < policy.minimumCooldown { return nil }

        let intervalSatisfied = elapsed >= policy.minimumInterval
        let idleSatisfied: Bool
        if let threshold = policy.idleThreshold, let idle = idleSeconds {
            idleSatisfied = idle >= threshold
        } else {
            idleSatisfied = false
        }

        guard intervalSatisfied || idleSatisfied else { return nil }

        let reason: String
        if idleSatisfied && !intervalSatisfied { reason = "idle-trigger" }
        else if intervalSatisfied && idleSatisfied { reason = "idle+interval" }
        else { reason = "scheduled-daily" }

        return try await manifester.runOnce(triggerReason: reason)
    }
}
