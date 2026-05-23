// Tests/SwooshLocalLLMTests/LiteRTDevicePolicyTests.swift
// Version: 0.9R
//
// Exercises the device-aware model selector. The selection math is pure
// (`recommendedModel(from:budget:)`) so it runs identically on macOS test
// hosts and iOS devices.

import XCTest
@testable import SwooshLocalLLM

final class LiteRTDevicePolicyTests: XCTestCase {

    private let e4b = LiteRTModelCatalog.gemma4E4B   // ~3.65 GB
    private let e2b = LiteRTModelCatalog.gemma4E2B   // ~2.58 GB
    private let headroom = LiteRTDevicePolicy.headroomBytes  // 1 GB

    // MARK: - Budget routing

    func test_recommendedModel_picksE4B_whenBudgetAmple() {
        // 5 GB device — should fit E4B (3.65 + 1 GB headroom = 4.65 GB).
        let budget: Int64 = 5_368_709_120
        let pick = LiteRTDevicePolicy.recommendedModel(from: [e4b, e2b], budget: budget)
        XCTAssertEqual(pick?.id, e4b.id, "5 GB budget should comfortably host E4B")
    }

    func test_recommendedModel_routesToE2B_whenE4BWontFit() {
        // 4 GB device — E4B + headroom (4.65) won't fit; E2B + headroom (3.58) does.
        let budget: Int64 = 4_294_967_296
        let pick = LiteRTDevicePolicy.recommendedModel(from: [e4b, e2b], budget: budget)
        XCTAssertEqual(pick?.id, e2b.id, "4 GB budget must route to E2B, never E4B")
    }

    func test_recommendedModel_returnsNil_whenNothingFits() {
        // 1 GB device — even E2B (2.58 + 1) won't fit.
        let budget: Int64 = 1_073_741_824
        let pick = LiteRTDevicePolicy.recommendedModel(from: [e4b, e2b], budget: budget)
        XCTAssertNil(pick, "Sub-budget should refuse any model, not silently pick the smallest")
    }

    func test_recommendedModel_returnsNil_forZeroBudget() {
        let pick = LiteRTDevicePolicy.recommendedModel(from: [e4b, e2b], budget: 0)
        XCTAssertNil(pick)
    }

    func test_recommendedModel_returnsNil_forEmptyCatalog() {
        let pick = LiteRTDevicePolicy.recommendedModel(from: [], budget: 10_000_000_000)
        XCTAssertNil(pick)
    }

    func test_recommendedModel_prefersLargestThatFits() {
        // Three candidates of ascending size. With budget that fits the
        // middle one, the picker should NOT silently pick the smallest.
        let small = makeModel(id: "small", bytes: 500_000_000)
        let mid = makeModel(id: "mid", bytes: 1_500_000_000)
        let big = makeModel(id: "big", bytes: 5_000_000_000)
        let budget: Int64 = mid.estimatedBytes + headroom // fits mid exactly
        let pick = LiteRTDevicePolicy.recommendedModel(
            from: [small, mid, big],
            budget: budget
        )
        XCTAssertEqual(pick?.id, mid.id, "Should pick mid — the largest that fits, not small")
    }

    func test_recommendedModel_headroomIsEnforced() {
        // Budget == model.estimatedBytes (no headroom) should fail.
        let budget = e2b.estimatedBytes
        let pick = LiteRTDevicePolicy.recommendedModel(from: [e2b], budget: budget)
        XCTAssertNil(pick, "Must enforce headroomBytes on top of estimatedBytes")
    }

    // MARK: - Fallback path

    func test_recommendedModel_noBudgetOverload_returnsSomething() {
        // The no-arg overload uses the live process budget and falls back
        // to the smallest model when nothing strictly fits. Verify it
        // doesn't return nil for the built-in catalog.
        let pick = LiteRTDevicePolicy.recommendedModel(from: LiteRTModelCatalog.all)
        XCTAssertNotNil(pick, "Convenience overload must always return some model")
    }

    func test_recommendedModel_zeroArg_returnsValidCatalogEntry() {
        let pick = LiteRTDevicePolicy.recommendedModel()
        XCTAssertTrue(
            LiteRTModelCatalog.all.contains(where: { $0.id == pick.id }),
            "Selection must come from the built-in catalog"
        )
    }

    // MARK: - Helpers

    private func makeModel(id: String, bytes: Int64) -> LiteRTModel {
        guard let url = URL(string: "https://example.test/\(id)") else {
            preconditionFailure("Invalid test URL for \(id)")
        }
        return LiteRTModel(
            id: id,
            displayName: id,
            family: "Test",
            downloadURL: url,
            estimatedBytes: bytes,
            parameters: "?",
            contextWindow: 0,
            supportsVision: false,
            supportsAudio: false,
            requiresExtendedAddressing: false
        )
    }
}
