// SwooshLocalVoice/LocalVoiceDevicePolicy.swift — 0.9R RAM-aware picker
//
// Mirrors `SwooshLocalLLM.LiteRTDevicePolicy` for the voice catalog:
// pick the largest model that fits in the current process budget with
// `headroomBytes` of slack for sampler state + vocoder buffers.
//
// Selection math is pure (`recommendedModel(from:budget:)`) so unit
// tests on macOS exercise it without an iOS runtime.

import Foundation
#if os(iOS)
import os
#endif

public enum LocalVoiceDevicePolicy {

    /// Bytes reserved beyond the weights for vocoder + sampler + audio
    /// buffer. Voice models are smaller than LLMs so 512 MB is enough.
    public static let headroomBytes: Int64 = 536_870_912 // 512 MB

    public static func availableMemoryBytes() -> Int64 {
        #if os(iOS)
        let value = os_proc_available_memory()
        if value > 0 { return Int64(value) }
        #endif
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        return max(0, total - 1_073_741_824) // assume 1 GB reserved on macOS test hosts
    }

    /// Pure selection — largest-first, headroom enforced, nil if nothing fits.
    public static func recommendedModel(
        from candidates: [LocalVoiceModel],
        budget: Int64
    ) -> LocalVoiceModel? {
        guard budget > 0, !candidates.isEmpty else { return nil }
        let sorted = candidates.sorted { $0.estimatedBytes > $1.estimatedBytes }
        for model in sorted where model.estimatedBytes + headroomBytes <= budget {
            return model
        }
        return nil
    }

    /// Live-budget overload. Falls back to the smallest model when
    /// nothing strictly fits (Kokoro is small enough that this is
    /// effectively always a real recommendation on iPhone).
    public static func recommendedModel(from candidates: [LocalVoiceModel]) -> LocalVoiceModel? {
        if let pick = recommendedModel(from: candidates, budget: availableMemoryBytes()) {
            return pick
        }
        return candidates.min(by: { $0.estimatedBytes < $1.estimatedBytes })
    }

    public static func recommendedModel() -> LocalVoiceModel {
        recommendedModel(from: LocalVoiceCatalog.all) ?? LocalVoiceCatalog.kokoro
    }

    public static func explainSelection(_ model: LocalVoiceModel) -> String {
        let budgetGB = Double(availableMemoryBytes()) / 1_073_741_824.0
        let needGB = Double(model.estimatedBytes + headroomBytes) / 1_073_741_824.0
        return String(
            format: "Selected %@ — device budget %.1f GB, model needs ~%.2f GB.",
            model.displayName, budgetGB, needGB
        )
    }
}
