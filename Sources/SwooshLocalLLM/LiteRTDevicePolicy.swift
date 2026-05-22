// SwooshLocalLLM/LiteRTDevicePolicy.swift — 0.9R Device-aware model picker
//
// Decides which `LiteRTModel` is safe to load on the current device given
// the process memory budget. On iOS the budget depends on whether the app
// has the `com.apple.developer.kernel.extended-virtual-addressing`
// entitlement (raises the per-process limit on devices with 6 GB+ RAM)
// and how much memory the OS is currently willing to hand us
// (`os_proc_available_memory`).
//
// The picker keeps a 1 GB headroom on top of the model's estimated bytes
// for KV-cache, scratch, and image buffers. If even the smallest model
// won't fit, returns nil — callers fall back to the daemon path.
//
// The selection math is pure (`recommendedModel(from:budget:)`) so the
// test target can exercise it on macOS without needing the iOS runtime.

import Foundation
#if os(iOS)
import os
#endif

public enum LiteRTDevicePolicy {

    /// Bytes the runtime expects to need beyond the model file itself
    /// (KV-cache, sampling buffers, image preprocessor). Conservative.
    public static let headroomBytes: Int64 = 1_073_741_824 // 1 GB

    /// Current per-process memory budget (bytes). On iOS this is what
    /// the OS guarantees the app can allocate before it gets jetsam-killed.
    /// On macOS or environments without `os_proc_available_memory`, falls
    /// back to a conservative estimate from `physicalMemory`.
    public static func availableMemoryBytes() -> Int64 {
        #if os(iOS)
        let value = os_proc_available_memory()
        if value > 0 { return Int64(value) }
        #endif
        // Fallback: use total RAM minus a conservative reserve so the
        // estimate is at least roughly the right order of magnitude.
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        return max(0, total - 2_147_483_648) // assume 2 GB reserved
    }

    /// Pure selection logic: pick the largest model from `candidates` that
    /// fits in `budget`. Largest-first, with `headroomBytes` reserved on
    /// top of each model's estimated size. Returns nil if nothing fits.
    /// Exposed for unit tests — production callers use the no-arg overload.
    public static func recommendedModel(
        from candidates: [LiteRTModel],
        budget: Int64
    ) -> LiteRTModel? {
        guard budget > 0, !candidates.isEmpty else { return nil }
        let sorted = candidates.sorted { $0.estimatedBytes > $1.estimatedBytes }
        for model in sorted where model.estimatedBytes + headroomBytes <= budget {
            return model
        }
        return nil
    }

    /// Convenience overload that queries the current process budget.
    public static func recommendedModel(from candidates: [LiteRTModel]) -> LiteRTModel? {
        let budget = availableMemoryBytes()
        if let pick = recommendedModel(from: candidates, budget: budget) {
            return pick
        }
        // Budget probe failed or nothing fits — return the smallest model
        // so the caller still has a download target. Load may fail later,
        // but the user keeps agency.
        return candidates.min(by: { $0.estimatedBytes < $1.estimatedBytes })
    }

    /// Convenience: pick from the built-in catalog. Returns the smallest
    /// model when nothing strictly fits, so the caller still has something
    /// to download — load may fail at runtime, but the user keeps agency.
    public static func recommendedModel() -> LiteRTModel {
        recommendedModel(from: LiteRTModelCatalog.all)
            ?? LiteRTModelCatalog.gemma4E2B
    }

    /// Human-readable reason string for surfacing in the UI when we
    /// down-route from E4B to E2B.
    public static func explainSelection(_ model: LiteRTModel) -> String {
        let budgetGB = Double(availableMemoryBytes()) / 1_073_741_824.0
        let needGB = Double(model.estimatedBytes + headroomBytes) / 1_073_741_824.0
        return String(
            format: "Selected %@ — device budget %.1f GB, model needs ~%.1f GB.",
            model.displayName, budgetGB, needGB
        )
    }
}
