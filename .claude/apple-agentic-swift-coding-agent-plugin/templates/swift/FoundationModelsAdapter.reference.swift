#if canImport(FoundationModels)
import Foundation
import FoundationModels

// Reference sketch. Verify exact API signatures against the installed Xcode SDK.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
struct FoundationModelsAdapter {
    func summarize(_ text: String) async throws -> String {
        // Pattern:
        // 1. Check SystemLanguageModel.default availability.
        // 2. Create LanguageModelSession with static instructions.
        // 3. Use guided generation for structured output when possible.
        // 4. Handle guardrail/model/context/cancellation errors.
        let model = SystemLanguageModel.default
        _ = model
        // Replace with current SDK call, e.g. LanguageModelSession(...).respond(to: ...)
        throw AgentError.modelUnavailable
    }
}
#endif
