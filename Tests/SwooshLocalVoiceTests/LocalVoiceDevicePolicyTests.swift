// Tests/SwooshLocalVoiceTests/LocalVoiceDevicePolicyTests.swift
// Version: 0.9R
//
// Mirrors LiteRTDevicePolicyTests: pure selection math, no iOS runtime.

import XCTest
@testable import SwooshLocalVoice

final class LocalVoiceDevicePolicyTests: XCTestCase {

    private let kokoro = LocalVoiceCatalog.kokoro
    private let omni = LocalVoiceCatalog.omniVoice
    private let headroom = LocalVoiceDevicePolicy.headroomBytes

    func test_recommendedModel_picksOmniVoice_whenBudgetAmple() {
        // 6 GB device — should fit OmniVoice (3.2 + 0.5 GB headroom = 3.7 GB).
        let budget: Int64 = 6_442_450_944
        let pick = LocalVoiceDevicePolicy.recommendedModel(from: [kokoro, omni], budget: budget)
        XCTAssertEqual(pick?.id, omni.id, "6 GB budget should fit OmniVoice")
    }

    func test_recommendedModel_routesToKokoro_whenOmniWontFit() {
        // 3 GB device — OmniVoice (3.2 + 0.5 = 3.7) doesn't fit; Kokoro (0.325 + 0.5) does.
        let budget: Int64 = 3_221_225_472
        let pick = LocalVoiceDevicePolicy.recommendedModel(from: [kokoro, omni], budget: budget)
        XCTAssertEqual(pick?.id, kokoro.id, "3 GB budget must route to Kokoro")
    }

    func test_recommendedModel_returnsNil_whenNothingFits() {
        // 400 MB budget — even Kokoro (0.325 + 0.5 headroom = 0.825) won't fit.
        let budget: Int64 = 400_000_000
        let pick = LocalVoiceDevicePolicy.recommendedModel(from: [kokoro, omni], budget: budget)
        XCTAssertNil(pick, "Sub-budget should refuse any model, not silently pick the smallest")
    }

    func test_recommendedModel_returnsNil_forZeroBudget() {
        XCTAssertNil(LocalVoiceDevicePolicy.recommendedModel(from: [kokoro, omni], budget: 0))
    }

    func test_recommendedModel_returnsNil_forEmptyCatalog() {
        XCTAssertNil(LocalVoiceDevicePolicy.recommendedModel(from: [], budget: 10_000_000_000))
    }

    func test_recommendedModel_headroomIsEnforced() {
        // Budget == model.estimatedBytes (no headroom) should fail.
        let budget = kokoro.estimatedBytes
        let pick = LocalVoiceDevicePolicy.recommendedModel(from: [kokoro], budget: budget)
        XCTAssertNil(pick, "Must enforce headroomBytes on top of estimatedBytes")
    }

    func test_recommendedModel_noBudgetOverload_returnsSomething() {
        let pick = LocalVoiceDevicePolicy.recommendedModel(from: LocalVoiceCatalog.all)
        XCTAssertNotNil(pick, "Convenience overload must always return some model")
    }

    func test_recommendedModel_zeroArg_returnsValidCatalogEntry() {
        let pick = LocalVoiceDevicePolicy.recommendedModel()
        XCTAssertTrue(
            LocalVoiceCatalog.all.contains(where: { $0.id == pick.id }),
            "Selection must come from the built-in catalog"
        )
    }
}
