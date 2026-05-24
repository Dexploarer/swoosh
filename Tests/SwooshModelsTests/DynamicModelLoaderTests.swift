// Tests/SwooshModelsTests/DynamicModelLoaderTests.swift — 0.9T
//
// Boundary coverage for `DynamicModelLoader` hardware-aware
// recommendation logic. The cutoffs (`MemoryBands.low/mid/high/workstation`)
// drive which Gemma + Qwen tags ship as the first-run defaults — silent
// drift would change the new-user experience on every Mac, so each
// boundary is pinned down here. Pure logic; no Ollama / no HF.

import Testing
import Foundation
@testable import SwooshModels

@Suite("DynamicModelLoader: Gemma recommendation bands")
struct DynamicModelLoaderGemmaTests {

    private func hardware(_ gb: Double) -> HardwareProfile {
        HardwareProfile(chip: "test", totalMemoryGB: gb, gpuCores: 1, neuralEngineCores: 1, osVersion: "test")
    }

    @Test("Below low band (8 GB) — Gemma E2B")
    func belowLow() {
        let tag = DynamicModelLoader.shared.defaultFallbackModel(hardware: hardware(8))
        #expect(tag == ModelDefaults.localOpenAIFallbackModelID)
    }

    @Test("At low boundary (12 GB) — already E4B, not E2B")
    func atLowBoundary() {
        // ..<lowMemoryGB is exclusive; 12.0 GB must land in the E4B band.
        let tag = DynamicModelLoader.shared.defaultFallbackModel(hardware: hardware(DynamicModelLoader.MemoryBands.lowMemoryGB))
        #expect(tag == ModelDefaults.localOpenAIModelID)
    }

    @Test("Default Mac band (16 GB / 32 GB) — Gemma E4B")
    func defaultBand() {
        for gb in [16.0, 24.0, 32.0, 47.0] as [Double] {
            let tag = DynamicModelLoader.shared.defaultFallbackModel(hardware: hardware(gb))
            #expect(tag == ModelDefaults.localOpenAIModelID, "\(gb) GB should pick E4B")
        }
    }

    @Test("At high boundary (48 GB) — already 26B MoE, not E4B")
    func atHighBoundary() {
        let tag = DynamicModelLoader.shared.defaultFallbackModel(hardware: hardware(DynamicModelLoader.MemoryBands.highMemoryGB))
        #expect(tag == "gemma4:26b")
    }

    @Test("Workstation band (48–95 GB) — Gemma 26B MoE")
    func workstationBand() {
        for gb in [48.0, 64.0, 95.0] as [Double] {
            let tag = DynamicModelLoader.shared.defaultFallbackModel(hardware: hardware(gb))
            #expect(tag == "gemma4:26b", "\(gb) GB should pick 26b")
        }
    }

    @Test("At workstation boundary (96 GB) — already 31B, not 26B")
    func atWorkstationBoundary() {
        let tag = DynamicModelLoader.shared.defaultFallbackModel(hardware: hardware(DynamicModelLoader.MemoryBands.workstationMemoryGB))
        #expect(tag == "gemma4:31b")
    }

    @Test("Mac Pro band (>=96 GB) — Gemma 31B dense")
    func macProBand() {
        for gb in [96.0, 128.0, 192.0, 512.0] as [Double] {
            let tag = DynamicModelLoader.shared.defaultFallbackModel(hardware: hardware(gb))
            #expect(tag == "gemma4:31b", "\(gb) GB should pick 31b")
        }
    }
}

@Suite("DynamicModelLoader: Qwen recommendation bands")
struct DynamicModelLoaderQwenTests {

    private func hardware(_ gb: Double) -> HardwareProfile {
        HardwareProfile(chip: "test", totalMemoryGB: gb, gpuCores: 1, neuralEngineCores: 1, osVersion: "test")
    }

    @Test("Below low band (8 GB) — Qwen 3.5 2B")
    func belowLow() {
        let tag = DynamicModelLoader.shared.recommendedQwenTag(hardware: hardware(8))
        #expect(tag == "qwen3.5:2b")
    }

    @Test("At low boundary (12 GB) — already 9B, not 2B")
    func atLowBoundary() {
        let tag = DynamicModelLoader.shared.recommendedQwenTag(hardware: hardware(DynamicModelLoader.MemoryBands.lowMemoryGB))
        #expect(tag == "qwen3.5:9b")
    }

    @Test("Mid band (16 GB / 23 GB) — Qwen 3.5 9B")
    func midBand() {
        for gb in [16.0, 20.0, 23.0] as [Double] {
            let tag = DynamicModelLoader.shared.recommendedQwenTag(hardware: hardware(gb))
            #expect(tag == "qwen3.5:9b", "\(gb) GB should pick 9b")
        }
    }

    @Test("At mid boundary (24 GB) — already 27B, not 9B")
    func atMidBoundary() {
        let tag = DynamicModelLoader.shared.recommendedQwenTag(hardware: hardware(DynamicModelLoader.MemoryBands.midMemoryGB))
        #expect(tag == "qwen3.6:27b")
    }

    @Test("High band (24–47 GB) — Qwen 3.6 27B dense")
    func highBand() {
        for gb in [24.0, 32.0, 47.0] as [Double] {
            let tag = DynamicModelLoader.shared.recommendedQwenTag(hardware: hardware(gb))
            #expect(tag == "qwen3.6:27b", "\(gb) GB should pick 27b")
        }
    }

    @Test("At high boundary (48 GB) — already 35B MoE, not 27B")
    func atHighBoundary() {
        let tag = DynamicModelLoader.shared.recommendedQwenTag(hardware: hardware(DynamicModelLoader.MemoryBands.highMemoryGB))
        #expect(tag == "qwen3.6:35b")
    }

    @Test("Workstation band (48–95 GB) — Qwen 3.6 35B MoE")
    func workstationBand() {
        for gb in [48.0, 64.0, 95.0] as [Double] {
            let tag = DynamicModelLoader.shared.recommendedQwenTag(hardware: hardware(gb))
            #expect(tag == "qwen3.6:35b", "\(gb) GB should pick 35b")
        }
    }

    @Test("At workstation boundary (96 GB) — already coder-next, not 35B")
    func atWorkstationBoundary() {
        let tag = DynamicModelLoader.shared.recommendedQwenTag(hardware: hardware(DynamicModelLoader.MemoryBands.workstationMemoryGB))
        #expect(tag == "qwen3-coder-next")
    }

    @Test("Mac Pro band (>=96 GB) — qwen3-coder-next")
    func macProBand() {
        for gb in [96.0, 192.0, 512.0] as [Double] {
            let tag = DynamicModelLoader.shared.recommendedQwenTag(hardware: hardware(gb))
            #expect(tag == "qwen3-coder-next", "\(gb) GB should pick coder-next")
        }
    }
}

@Suite("DynamicModelLoader: recommendedLocalModels trio")
struct DynamicModelLoaderTrioTests {

    private func hardware(_ gb: Double) -> HardwareProfile {
        HardwareProfile(chip: "test", totalMemoryGB: gb, gpuCores: 1, neuralEngineCores: 1, osVersion: "test")
    }

    @Test("Returns Gemma + Qwen + FunctionGemma — exactly three entries")
    func threeEntries() {
        let trio = DynamicModelLoader.shared.recommendedLocalModels(hardware: hardware(16))
        #expect(trio.count == 3)
    }

    @Test("Gemma slot is the default fallback flag, Qwen + FunctionGemma are not")
    func defaultFlagPosition() {
        let trio = DynamicModelLoader.shared.recommendedLocalModels(hardware: hardware(16))
        #expect(trio.first?.isDefaultFallback == true)
        let defaults = trio.filter { $0.isDefaultFallback }
        #expect(defaults.count == 1, "Exactly one of the trio should be marked as the default fallback")
    }

    @Test("FunctionGemma always appears with phone-routing tag")
    func functionGemmaPresent() {
        let trio = DynamicModelLoader.shared.recommendedLocalModels(hardware: hardware(96))
        #expect(trio.contains { $0.tag == ModelDefaults.phoneFunctionCallingModelID })
    }
}

@Suite("DynamicModelLoader.MemoryBands")
struct DynamicModelLoaderMemoryBandsTests {

    @Test("Bands are strictly ascending")
    func ascending() {
        let bands = [
            DynamicModelLoader.MemoryBands.lowMemoryGB,
            DynamicModelLoader.MemoryBands.midMemoryGB,
            DynamicModelLoader.MemoryBands.highMemoryGB,
            DynamicModelLoader.MemoryBands.workstationMemoryGB,
        ]
        for i in 0..<(bands.count - 1) {
            #expect(bands[i] < bands[i + 1])
        }
    }

    @Test("Documented cutoffs are 12 / 24 / 48 / 96 GB")
    func documentedValues() {
        // These four numbers are the contract — changing them silently
        // would steer first-run defaults onto different tags. Pin them
        // here so the change is visible in a test diff.
        #expect(DynamicModelLoader.MemoryBands.lowMemoryGB == 12)
        #expect(DynamicModelLoader.MemoryBands.midMemoryGB == 24)
        #expect(DynamicModelLoader.MemoryBands.highMemoryGB == 48)
        #expect(DynamicModelLoader.MemoryBands.workstationMemoryGB == 96)
    }
}
