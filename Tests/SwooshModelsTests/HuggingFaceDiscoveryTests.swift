// Tests/SwooshModelsTests/HuggingFaceDiscoveryTests.swift — 0.9T
//
// Pure-logic coverage for `HuggingFaceDiscovery.estimateSize` (the 27-row
// size-pattern table that maps HF model names to size tier + memory
// estimate) and `HuggingFaceDiscovery.extractLicense` (parses `license:*`
// tag prefixes). No network — these are heuristics that drive what tier
// a discovered model is shown at, so silent drift is the risk we're
// pinning down here.

import Testing
import Foundation
@testable import SwooshModels

@Suite("HuggingFaceDiscovery.estimateSize")
struct HuggingFaceDiscoveryEstimateSizeTests {

    @Test("Massive band: 235B → massive / ~130 GB")
    func massive_235B() {
        let (params, tier, mem) = HuggingFaceDiscovery.estimateSize("Qwen3-235B-Instruct")
        #expect(params == "235B")
        #expect(tier == .massive)
        #expect(mem == 130)
    }

    @Test("Massive band: 70B → massive / 45 GB")
    func massive_70B() {
        let (params, tier, mem) = HuggingFaceDiscovery.estimateSize("Llama-70B-it")
        #expect(params == "70B")
        #expect(tier == .massive)
        #expect(mem == 45)
    }

    @Test("XLarge band: 32B / 30B / 27B / 22B all route to xlarge")
    func xlarge() {
        for pattern in ["32B", "30B", "27B", "22B"] {
            let (_, tier, _) = HuggingFaceDiscovery.estimateSize("model-\(pattern)-it")
            #expect(tier == .xlarge, "\(pattern) must map to .xlarge")
        }
    }

    @Test("Large band: 14B / 13B / 12B")
    func large() {
        for pattern in ["14B", "13B", "12B"] {
            let (_, tier, _) = HuggingFaceDiscovery.estimateSize("model-\(pattern)")
            #expect(tier == .large, "\(pattern) must map to .large")
        }
    }

    @Test("Medium band: 9B / 8B / 7B")
    func medium() {
        for pattern in ["9B", "8B", "7B"] {
            let (_, tier, _) = HuggingFaceDiscovery.estimateSize("X-\(pattern)-base")
            #expect(tier == .medium, "\(pattern) must map to .medium")
        }
    }

    @Test("Small band: 4B / 3B / 2B / 1.7B / 1.5B")
    func small() {
        for pattern in ["4B", "3B", "2B", "1.7B", "1.5B"] {
            let (_, tier, _) = HuggingFaceDiscovery.estimateSize("X-\(pattern)-it")
            #expect(tier == .small, "\(pattern) must map to .small")
        }
    }

    @Test("Micro band: 1B / 0.8B / 0.6B / 0.5B / 500M")
    func micro() {
        for pattern in ["1B", "0.8B", "0.6B", "0.5B", "500M"] {
            let (_, tier, _) = HuggingFaceDiscovery.estimateSize("X-\(pattern)")
            #expect(tier == .micro, "\(pattern) must map to .micro")
        }
    }

    @Test("Nano band: 0.3B / 350M / 250M / 137M / 82M")
    func nano() {
        for pattern in ["0.3B", "350M", "250M", "137M", "82M"] {
            let (_, tier, _) = HuggingFaceDiscovery.estimateSize("X-\(pattern)")
            #expect(tier == .nano, "\(pattern) must map to .nano")
        }
    }

    @Test("Case-insensitive: lowercase patterns still match")
    func caseInsensitive() {
        let (params, tier, _) = HuggingFaceDiscovery.estimateSize("qwen-7b-instruct")
        #expect(params == "7B")
        #expect(tier == .medium)
    }

    @Test("Unknown pattern falls back to medium/5GB without crashing")
    func unknown() {
        let (params, tier, mem) = HuggingFaceDiscovery.estimateSize("some-random-model")
        #expect(params == "Unknown")
        #expect(tier == .medium)
        #expect(mem == 5.0)
    }

    @Test("Memory estimate is monotonic by tier")
    func monotonicByTier() {
        // Pick one representative pattern per tier, in ascending tier order.
        let samples: [String] = [
            "82M",   // nano
            "0.6B",  // micro
            "2B",    // small
            "7B",    // medium
            "13B",   // large
            "30B",   // xlarge
            "70B",   // massive
        ]
        let mems = samples.map { HuggingFaceDiscovery.estimateSize($0).memGB }
        for i in 0..<(mems.count - 1) {
            #expect(mems[i] < mems[i + 1], "memory must grow tier-by-tier; \(samples[i])→\(mems[i]) >= \(samples[i + 1])→\(mems[i + 1])")
        }
    }

    @Test("Largest match wins when multiple patterns nest in a name")
    func largestMatchWins() {
        // "70B-instruct-1B" contains both "70B" and "1B" — table iterates
        // largest-to-smallest, so 70B should win.
        let (params, tier, _) = HuggingFaceDiscovery.estimateSize("Llama-70B-instruct-1B")
        #expect(params == "70B")
        #expect(tier == .massive)
    }
}

@Suite("HuggingFaceDiscovery.extractLicense")
struct HuggingFaceDiscoveryExtractLicenseTests {

    @Test("Returns license value when tag is present")
    func licensePresent() {
        let license = HuggingFaceDiscovery.extractLicense(["transformers", "license:apache-2.0", "text-generation"])
        #expect(license == "apache-2.0")
    }

    @Test("Returns Unknown when no license tag")
    func licenseAbsent() {
        let license = HuggingFaceDiscovery.extractLicense(["transformers", "text-generation"])
        #expect(license == "Unknown")
    }

    @Test("Returns Unknown for empty tag list")
    func empty() {
        let license = HuggingFaceDiscovery.extractLicense([])
        #expect(license == "Unknown")
    }

    @Test("First license tag wins when multiple present")
    func firstWins() {
        let license = HuggingFaceDiscovery.extractLicense(["license:mit", "license:apache-2.0"])
        #expect(license == "mit")
    }
}
