// SwooshObservability/MetricsCollector.swift — Aggregate performance metrics
//
// Collects latency, throughput, error rates, and other metrics
// across providers and tools for the observability dashboard.

import Foundation
import Logging

// ═══════════════════════════════════════════════════════════════════
// MARK: - Metrics collector
// ═══════════════════════════════════════════════════════════════════

/// Central metrics aggregator for the Swoosh runtime.
public actor MetricsCollector {
    private let logger = Logger(label: "swoosh.metrics")
    private var latencyBuckets: [String: [TimeInterval]] = [:]
    private var counters: [String: Int] = [:]
    private var gauges: [String: Double] = [:]
    private let maxBucketSize: Int

    public init(maxBucketSize: Int = 1000) {
        self.maxBucketSize = maxBucketSize
    }

    // ── Latency tracking ──

    /// Record a latency sample for a named operation.
    public func recordLatency(_ operation: String, duration: TimeInterval) {
        latencyBuckets[operation, default: []].append(duration)
        // Rolling window
        if latencyBuckets[operation]!.count > maxBucketSize {
            latencyBuckets[operation]!.removeFirst()
        }
    }

    /// Get latency percentiles for an operation.
    public func latencyPercentiles(_ operation: String) -> LatencyStats? {
        guard let bucket = latencyBuckets[operation], !bucket.isEmpty else { return nil }
        let sorted = bucket.sorted()
        let count = sorted.count
        return LatencyStats(
            p50: sorted[count / 2],
            p90: sorted[Int(Double(count) * 0.9)],
            p95: sorted[Int(Double(count) * 0.95)],
            p99: sorted[min(Int(Double(count) * 0.99), count - 1)],
            avg: sorted.reduce(0, +) / Double(count),
            min: sorted.first ?? 0,
            max: sorted.last ?? 0,
            count: count
        )
    }

    // ── Counters ──

    /// Increment a named counter.
    public func increment(_ name: String, by amount: Int = 1) {
        counters[name, default: 0] += amount
    }

    /// Get a counter value.
    public func counter(_ name: String) -> Int {
        counters[name, default: 0]
    }

    // ── Gauges ──

    /// Set a gauge value (current state, like active agents).
    public func setGauge(_ name: String, value: Double) {
        gauges[name] = value
    }

    /// Get a gauge value.
    public func gauge(_ name: String) -> Double {
        gauges[name, default: 0]
    }

    // ── Snapshot ──

    /// Full metrics snapshot.
    public func snapshot() -> MetricsSnapshot {
        MetricsSnapshot(
            counters: counters,
            gauges: gauges,
            latency: Dictionary(uniqueKeysWithValues:
                latencyBuckets.keys.compactMap { key in
                    latencyPercentiles(key).map { (key, $0) }
                }
            ),
            timestamp: Date()
        )
    }

    // ── Convenience methods for common metrics ──

    public func recordInference(provider: String, model: String, duration: TimeInterval) {
        recordLatency("inference.\(provider).\(model)", duration: duration)
        recordLatency("inference.all", duration: duration)
        increment("inference.count")
        increment("inference.\(provider).count")
    }

    public func recordToolCall(toolID: String, duration: TimeInterval, success: Bool) {
        recordLatency("tool.\(toolID)", duration: duration)
        recordLatency("tool.all", duration: duration)
        increment("tool.count")
        if !success { increment("tool.errors") }
    }

    public func recordApproval(decision: String, waitDuration: TimeInterval) {
        recordLatency("approval.wait", duration: waitDuration)
        increment("approval.\(decision)")
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Supporting types
// ═══════════════════════════════════════════════════════════════════

public struct LatencyStats: Sendable {
    public let p50: TimeInterval
    public let p90: TimeInterval
    public let p95: TimeInterval
    public let p99: TimeInterval
    public let avg: TimeInterval
    public let min: TimeInterval
    public let max: TimeInterval
    public let count: Int
}

public struct MetricsSnapshot: Sendable {
    public let counters: [String: Int]
    public let gauges: [String: Double]
    public let latency: [String: LatencyStats]
    public let timestamp: Date
}
