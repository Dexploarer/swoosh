// SwooshCore/LocalDiagnosticProvider.swift — Deterministic fallback provider
//
// Returns deterministic responses that use approved memories in the reply.
// Used when no model provider is configured and by prompt-pipeline tests.

import Foundation

/// A deterministic model provider for offline diagnostics.
/// Returns a response that references the approved memories injected in the prompt.
public struct LocalDiagnosticProvider: ModelProvider, Sendable {
    public let providerID: String = "local-diagnostic"
    public let modelName: String = "swoosh-local-diagnostic-v1"

    private let cannedResponse: String?

    public init(cannedResponse: String? = nil) {
        self.cannedResponse = cannedResponse
    }

    public func complete(_ request: ModelCompletionRequest) async throws -> ModelCompletionResponse {
        if let canned = cannedResponse {
            return ModelCompletionResponse(
                content: canned,
                model: modelName,
                usage: ModelUsage(promptTokens: 100, completionTokens: 50, totalTokens: 150)
            )
        }

        let systemPrompt = request.messages.first(where: { $0.role == .system })?.content ?? ""
        let userQuery = request.messages.last(where: { $0.role == .user })?.content ?? ""

        var responseLines: [String] = []
        responseLines.append("Hi — I'm Detour, but I can't reason yet because no model provider is configured on this Mac.")
        responseLines.append("You're seeing the local diagnostic fallback, which only reflects the prompt back to you.")
        responseLines.append("")

        if systemPrompt.contains("Approved Memories") {
            responseLines.append("Approved context visible to me:")
            let memLines = systemPrompt.components(separatedBy: "\n")
                .filter { $0.hasPrefix("- [") }
            for memLine in memLines {
                responseLines.append("- \(memLine.dropFirst(2))")
            }
        } else {
            responseLines.append("No approved memories available yet.")
        }

        responseLines.append("")
        responseLines.append("You said: \(userQuery)")
        responseLines.append("")
        responseLines.append("To enable real replies, add a provider key on the Mac. For example:")
        responseLines.append("  swoosh provider auth openai --api-key sk-…")
        responseLines.append("  swoosh provider auth anthropic --api-key sk-ant-…")
        responseLines.append("…then restart swooshd.")

        return ModelCompletionResponse(
            content: responseLines.joined(separator: "\n"),
            model: modelName,
            usage: ModelUsage(promptTokens: systemPrompt.count / 4, completionTokens: 50, totalTokens: systemPrompt.count / 4 + 50)
        )
    }
}
