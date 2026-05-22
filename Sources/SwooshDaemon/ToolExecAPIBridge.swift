// SwooshDaemon/ToolExecAPIBridge.swift — Tool execution ↔ HTTP API
//
// POST /api/tools/:name/execute invokes a registered tool by name.
// The bearer-token caller represents the user, so the context uses
// isModelInvocation=false; the firewall + approval + audit pipeline
// still applies via the normal `ToolRegistry.call` path.

import Foundation
import SwooshAPI
import SwooshClient
import SwooshTools

extension SwooshDaemon {
    static func executeToolResponse(
        registry: ToolRegistry,
        name: String,
        request: ToolExecuteRequest
    ) async throws -> ToolExecuteResponse {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw APIError.badRequest("tool name is empty")
        }
        let args = try decodeArgs(request.argsJSON)
        let context = ToolContext(
            sessionID: request.sessionID ?? "api-execute",
            isModelInvocation: false,
            callerIdentity: "api"
        )
        let started = Date()
        do {
            let output = try await registry.call(
                name: ToolName(trimmed),
                input: args,
                context: context
            )
            let outputJSON = encodeOutput(output)
            let durationMs = Int(Date().timeIntervalSince(started) * 1000)
            return ToolExecuteResponse(
                toolName: trimmed,
                success: true,
                outputJSON: outputJSON,
                error: nil,
                durationMs: durationMs
            )
        } catch {
            let durationMs = Int(Date().timeIntervalSince(started) * 1000)
            return ToolExecuteResponse(
                toolName: trimmed,
                success: false,
                outputJSON: nil,
                error: error.localizedDescription,
                durationMs: durationMs
            )
        }
    }

    // MARK: - private

    private static func decodeArgs(_ raw: String) throws -> JSONValue {
        guard !raw.isEmpty else { return .object([:]) }
        guard let data = raw.data(using: .utf8) else {
            throw APIError.badRequest("argsJSON is not valid UTF-8")
        }
        do {
            return try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw APIError.badRequest("argsJSON is not valid JSON")
        }
    }

    private static func encodeOutput(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(value), let s = String(data: data, encoding: .utf8) {
            return s
        }
        return "{}"
    }
}
