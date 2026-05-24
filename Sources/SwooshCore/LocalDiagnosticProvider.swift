// SwooshCore/LocalDiagnosticProvider.swift — 0.9S Deterministic fallback provider
//
// Returns deterministic responses that use approved memories in the reply.
// Used when no model provider is configured and by prompt-pipeline tests.

import Foundation
import SwooshTools

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

        if let diagnosticToolResponse = toolDiagnosticResponse(for: request) {
            return diagnosticToolResponse
        }

        let systemPrompt = request.messages.first(where: { $0.role == .system })?.content ?? ""
        let userQuery = request.messages.last(where: { $0.role == .user })?.content ?? ""

        var responseLines: [String] = []
        responseLines.append("Hi — I'm Swoosh, but I can't reason yet because no model provider is configured on this Mac.")
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
        responseLines.append("  swoosh provider auth openrouter --api-key sk-or-…")
        responseLines.append("  swoosh provider auth eliza-cloud --api-key sk-…")
        responseLines.append("…then restart swooshd.")

        return ModelCompletionResponse(
            content: responseLines.joined(separator: "\n"),
            model: modelName,
            usage: ModelUsage(promptTokens: systemPrompt.count / 4, completionTokens: 50, totalTokens: systemPrompt.count / 4 + 50)
        )
    }

    private func toolDiagnosticResponse(for request: ModelCompletionRequest) -> ModelCompletionResponse? {
        if let toolResult = request.messages.last(where: { $0.role == .tool })?.content,
           let toolName = toolName(fromToolResult: toolResult) {
            return ModelCompletionResponse(
                content: "I used `\(toolName)` through the Swoosh tool loop.\n\n\(toolResult)",
                model: modelName,
                usage: ModelUsage(promptTokens: 100, completionTokens: 80, totalTokens: 180)
            )
        }

        let userQuery = request.messages.last(where: { $0.role == .user })?.content ?? ""
        guard let descriptor = requestedToolDescriptor(in: userQuery, tools: request.tools) else {
            return nil
        }
        return ModelCompletionResponse(
            content: "",
            model: modelName,
            usage: ModelUsage(promptTokens: 80, completionTokens: 10, totalTokens: 90),
            toolCalls: [
                NativeToolCall(name: descriptor.name, arguments: toolArguments(in: userQuery)),
            ],
            isToolCallMode: true
        )
    }

    private func requestedToolDescriptor(
        in query: String,
        tools: [SwooshTools.ToolDescriptor]
    ) -> SwooshTools.ToolDescriptor? {
        let normalized = query.lowercased()
        guard normalized.contains("tool") || normalized.contains("call") || normalized.contains("run") || normalized.contains("use") else {
            return nil
        }
        return tools
            .sorted { $0.name.count > $1.name.count }
            .first { normalized.contains($0.name.lowercased()) }
    }

    private func toolArguments(in query: String) -> JSONValue {
        guard let start = query.firstIndex(of: "{"),
              let end = query.lastIndex(of: "}"),
              start <= end else {
            return .object([:])
        }
        let json = String(query[start...end])
        guard let data = json.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return .object([:])
        }
        return value
    }

    private func toolName(fromToolResult toolResult: String) -> String? {
        toolResult.components(separatedBy: "\n")
            .first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- tool:") }?
            .replacingOccurrences(of: "- tool:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
