// SwooshCore/LocalStubProvider.swift — Deterministic test provider
//
// Returns canned responses that use approved memories in the reply.
// Used for testing that the prompt pipeline works correctly.

import Foundation

/// A deterministic model provider for tests.
/// Returns a response that references the approved memories injected in the prompt.
public struct LocalStubProvider: ModelProvider, Sendable {
    public let providerID: String = "stub"
    public let modelName: String = "swoosh-stub-v1"

    private let cannedResponse: String?

    public init(cannedResponse: String? = nil) {
        self.cannedResponse = cannedResponse
    }

    public func complete(_ request: ModelCompletionRequest) async throws -> ModelCompletionResponse {
        // If a canned response is provided, use it
        if let canned = cannedResponse {
            return ModelCompletionResponse(
                content: canned,
                model: modelName,
                usage: ModelUsage(promptTokens: 100, completionTokens: 50, totalTokens: 150)
            )
        }

        // Default: generate a response that proves we received the approved memories
        let systemPrompt = request.messages.first(where: { $0.role == .system })?.content ?? ""
        let userQuery = request.messages.last(where: { $0.role == .user })?.content ?? ""

        var responseLines: [String] = []
        responseLines.append("Based on your approved context, here's what I can help with:")
        responseLines.append("")

        // Parse memories from system prompt to prove they were injected
        if systemPrompt.contains("Approved Memories") {
            let memLines = systemPrompt.components(separatedBy: "\n")
                .filter { $0.hasPrefix("- [") }
            for memLine in memLines {
                responseLines.append("  • I know: \(memLine.dropFirst(2))")
            }
        } else {
            responseLines.append("  No approved memories available yet.")
        }

        responseLines.append("")
        responseLines.append("Your question: \(userQuery)")

        return ModelCompletionResponse(
            content: responseLines.joined(separator: "\n"),
            model: modelName,
            usage: ModelUsage(promptTokens: systemPrompt.count / 4, completionTokens: 50, totalTokens: systemPrompt.count / 4 + 50)
        )
    }
}
