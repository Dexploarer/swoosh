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
    func massive235B() {
        let size = HuggingFaceDiscovery.estimateSize("Qwen3-235B-Instruct")
        #expect(size.params == "235B")
        #expect(size.tier == .massive)
        #expect(size.memoryGB == 130)
    }

    @Test("Massive band: 70B → massive / 45 GB")
    func massive70B() {
        let size = HuggingFaceDiscovery.estimateSize("Llama-70B-it")
        #expect(size.params == "70B")
        #expect(size.tier == .massive)
        #expect(size.memoryGB == 45)
    }

    @Test("XLarge band: 32B / 30B / 27B / 22B all route to xlarge")
    func xlarge() {
        for pattern in ["32B", "30B", "27B", "22B"] {
            let size = HuggingFaceDiscovery.estimateSize("model-\(pattern)-it")
            #expect(size.tier == .xlarge, "\(pattern) must map to .xlarge")
        }
    }

    @Test("Large band: 14B / 13B / 12B")
    func large() {
        for pattern in ["14B", "13B", "12B"] {
            let size = HuggingFaceDiscovery.estimateSize("model-\(pattern)")
            #expect(size.tier == .large, "\(pattern) must map to .large")
        }
    }

    @Test("Medium band: 9B / 8B / 7B")
    func medium() {
        for pattern in ["9B", "8B", "7B"] {
            let size = HuggingFaceDiscovery.estimateSize("X-\(pattern)-base")
            #expect(size.tier == .medium, "\(pattern) must map to .medium")
        }
    }

    @Test("Small band: 4B / 3B / 2B / 1.7B / 1.5B")
    func small() {
        for pattern in ["4B", "3B", "2B", "1.7B", "1.5B"] {
            let size = HuggingFaceDiscovery.estimateSize("X-\(pattern)-it")
            #expect(size.tier == .small, "\(pattern) must map to .small")
        }
    }

    @Test("Micro band: 1B / 0.8B / 0.6B / 0.5B / 500M")
    func micro() {
        for pattern in ["1B", "0.8B", "0.6B", "0.5B", "500M"] {
            let size = HuggingFaceDiscovery.estimateSize("X-\(pattern)")
            #expect(size.tier == .micro, "\(pattern) must map to .micro")
        }
    }

    @Test("Nano band: 0.3B / 350M / 250M / 137M / 82M")
    func nano() {
        for pattern in ["0.3B", "350M", "250M", "137M", "82M"] {
            let size = HuggingFaceDiscovery.estimateSize("X-\(pattern)")
            #expect(size.tier == .nano, "\(pattern) must map to .nano")
        }
    }

    @Test("Case-insensitive: lowercase patterns still match")
    func caseInsensitive() {
        let size = HuggingFaceDiscovery.estimateSize("qwen-7b-instruct")
        #expect(size.params == "7B")
        #expect(size.tier == .medium)
    }

    @Test("Unknown pattern falls back to medium/5GB without crashing")
    func unknown() {
        let size = HuggingFaceDiscovery.estimateSize("some-random-model")
        #expect(size.params == "Unknown")
        #expect(size.tier == .medium)
        #expect(size.memoryGB == 5.0)
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
            "70B"    // massive
        ]
        let mems = samples.map { HuggingFaceDiscovery.estimateSize($0).memoryGB }
        for idx in 0..<(mems.count - 1) {
            let lhs = "\(samples[idx])→\(mems[idx])"
            let rhs = "\(samples[idx + 1])→\(mems[idx + 1])"
            #expect(mems[idx] < mems[idx + 1], "memory must grow tier-by-tier; \(lhs) >= \(rhs)")
        }
    }

    @Test("Largest match wins when multiple patterns nest in a name")
    func largestMatchWins() {
        // "70B-instruct-1B" contains both "70B" and "1B" — table iterates
        // largest-to-smallest, so 70B should win.
        let size = HuggingFaceDiscovery.estimateSize("Llama-70B-instruct-1B")
        #expect(size.params == "70B")
        #expect(size.tier == .massive)
    }

    @Test("1.7B is recognized and does NOT fall to the 7B tier (regression test)")
    func decimalDoesNotFallToInteger() {
        // This is the original bug: `upper.contains("7B")` matched inside
        // "1.7B" and reported `.medium / 5 GB`. The anchored matcher must
        // reject that and let the iteration reach the "1.7B" row.
        let size = HuggingFaceDiscovery.estimateSize("Qwen-1.7B-Instruct")
        #expect(size.params == "1.7B")
        #expect(size.tier == .small)
        #expect(size.memoryGB == 1.2)
    }

    @Test("500M wins over 0.3B when both appear (largest-first invariant)")
    func largestFirstAcrossNotations() {
        // Regression test for a table-ordering bug: 500M (= 0.5B) was listed
        // AFTER 0.3B in the size table, so a hypothetical name carrying
        // both spellings would have falsely picked the smaller 0.3B row.
        // The fix re-orders the table strictly by parameter count, so the
        // larger 500M (micro / 0.35 GB) wins over the smaller 0.3B
        // (nano / 0.2 GB).
        let size = HuggingFaceDiscovery.estimateSize("X-0.3B-500M")
        #expect(size.params == "500M")
        #expect(size.tier == .micro)
        #expect(size.memoryGB == 0.35)
    }
}

@Suite("HuggingFaceDiscovery.containsAnchored")
struct HFDiscoveryContainsAnchoredTests {

    @Test("Matches at start of string")
    func startOfString() {
        #expect(HuggingFaceDiscovery.containsAnchored("70B-INSTRUCT", pattern: "70B"))
        #expect(HuggingFaceDiscovery.containsAnchored("1.7B", pattern: "1.7B"))
    }

    @Test("Matches when preceded by dash, underscore, or slash")
    func nonNumericDelimiters() {
        #expect(HuggingFaceDiscovery.containsAnchored("QWEN-7B-IT", pattern: "7B"))
        #expect(HuggingFaceDiscovery.containsAnchored("MODEL_7B_BASE", pattern: "7B"))
        #expect(HuggingFaceDiscovery.containsAnchored("ORG/QWEN-7B", pattern: "7B"))
        // Trailing position is fine — anchor only checks the prefix character.
        #expect(HuggingFaceDiscovery.containsAnchored("QWEN-70B", pattern: "70B"))
    }

    @Test("Rejects when preceded by a digit")
    func rejectsDigitPrefix() {
        // "17B" inside "Custom-117B" must not match the "7B" row.
        #expect(!HuggingFaceDiscovery.containsAnchored("CUSTOM-117B", pattern: "7B"))
        // "32B" must not match "2B".
        #expect(!HuggingFaceDiscovery.containsAnchored("MODEL-32B", pattern: "2B"))
    }

    @Test("Rejects when preceded by a dot")
    func rejectsDotPrefix() {
        // "1.7B" must not match "7B".
        #expect(!HuggingFaceDiscovery.containsAnchored("X-1.7B", pattern: "7B"))
        // "0.3B" must not match "3B".
        #expect(!HuggingFaceDiscovery.containsAnchored("X-0.3B", pattern: "3B"))
    }

    @Test("Returns false when pattern is absent")
    func notPresent() {
        #expect(!HuggingFaceDiscovery.containsAnchored("LLAMA-13B", pattern: "70B"))
    }

    @Test("Falls through a digit-prefixed false match to a valid later match")
    func skipsBadCandidate() {
        // "0.7B" contains "7B" preceded by ".", but ALSO contains "7B"
        // nowhere else. So `containsAnchored(_:"7B")` should be false.
        #expect(!HuggingFaceDiscovery.containsAnchored("X-0.7B", pattern: "7B"))
        // But "0.7B-then-7B" contains a second "7B" at a valid anchor.
        #expect(HuggingFaceDiscovery.containsAnchored("X-0.7B-7B", pattern: "7B"))
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
