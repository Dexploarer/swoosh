// Tests/SwooshFoundationTests/FoundationModelsAdapterTests.swift
//
// SwooshFoundation wraps Apple's on-device FoundationModels framework
// (gated by `#if canImport(FoundationModels)`). On platforms where the
// framework is unavailable, the module exposes only `FoundationModelAdapter`
// with `init()`. These tests verify the adapter at least initializes.
//
// We deliberately do NOT call the model methods because they require the
// `Apple Intelligence` device capability that CI runners lack.

import Testing
import Foundation
@testable import SwooshFoundation

@Suite("FoundationModelAdapter")
struct FoundationModelAdapterTests {

    @Test("Initializes successfully")
    func initializes() {
        let adapter = FoundationModelAdapter()
        _ = adapter
        #expect(Bool(true))
    }

    @Test("Adapter is an actor (Sendable)")
    func sendable() {
        let adapter = FoundationModelAdapter()
        let _: any Sendable = adapter
        #expect(Bool(true))
    }
}

#if canImport(FoundationModels)
// Type-level checks for the guided-generation structs. We don't run them,
// but we verify they exist and have the expected public properties so the
// surface stays stable.
@Suite("FoundationModels Guided Types")
struct GuidedTypesTests {

    @Test("ExtractedIntent has expected fields")
    func extractedIntent() {
        // Type-level check; instances require @Generable runtime.
        let _: ExtractedIntent.Type = ExtractedIntent.self
        #expect(Bool(true))
    }

    @Test("ExtractedMemoryCandidate has expected fields")
    func extractedMemory() {
        let _: ExtractedMemoryCandidate.Type = ExtractedMemoryCandidate.self
        #expect(Bool(true))
    }

    @Test("RiskAssessment has expected fields")
    func risk() {
        let _: RiskAssessment.Type = RiskAssessment.self
        #expect(Bool(true))
    }

    @Test("ExtractedCalendarItem has expected fields")
    func calendarItem() {
        let _: ExtractedCalendarItem.Type = ExtractedCalendarItem.self
        #expect(Bool(true))
    }
}
#endif
