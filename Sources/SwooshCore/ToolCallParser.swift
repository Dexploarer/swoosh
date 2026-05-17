// SwooshCore/ToolCallParser.swift — Tool-call parser (0.4B)
//
// Converts model output into either assistant text or a typed ToolExecutionRequest.
// Supports native provider tool calls and strict fallback JSON.
// Does NOT parse arbitrary JSON from normal text.

import Foundation
import SwooshTools

// MARK: - Parsed model turn

public enum ParsedModelTurn: Sendable {
    case assistantText(String)
    case toolCall(ToolExecutionRequest)
    case multipleToolCalls([ToolExecutionRequest])
}

// MARK: - Native tool call representation

/// Represents a tool call from a model provider's native tool-calling API.
public struct NativeToolCall: Sendable {
    public let id: String
    public let name: String
    public let arguments: JSONValue

    public init(id: String = UUID().uuidString, name: String, arguments: JSONValue) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

// MARK: - Tool-call parsing protocol

public protocol ToolCallParsing: Sendable {
    func parse(
        response: ModelCompletionResponse,
        sessionID: String,
        origin: ToolCallOrigin
    ) throws -> ParsedModelTurn
}

// MARK: - Strict fallback JSON

/// The strict JSON format the model can emit when in tool-call mode.
/// ```json
/// { "swoosh_tool_call": { "name": "...", "arguments": { ... } } }
/// ```
struct StrictToolCallJSON: Codable {
    let swoosh_tool_call: ToolCallPayload

    struct ToolCallPayload: Codable {
        let name: String
        let arguments: JSONValue
    }

    static func decode(_ text: String) throws -> ToolCallPayload {
        guard let data = text.data(using: .utf8) else {
            throw ToolCallParserError.malformedJSON("Cannot convert text to data")
        }
        let decoded = try JSONDecoder().decode(StrictToolCallJSON.self, from: data)
        guard !decoded.swoosh_tool_call.name.isEmpty else {
            throw ToolCallParserError.missingToolName
        }
        return decoded.swoosh_tool_call
    }
}

// MARK: - Parser errors

public enum ToolCallParserError: Error, Sendable {
    case malformedJSON(String)
    case missingToolName
    case invalidToolName(String)
}

// MARK: - Concrete parser

public struct ToolCallParser: ToolCallParsing {
    public init() {}

    public func parse(
        response: ModelCompletionResponse,
        sessionID: String,
        origin: ToolCallOrigin
    ) throws -> ParsedModelTurn {
        // 1. Check native provider tool calls first
        if !response.toolCalls.isEmpty {
            if response.toolCalls.count == 1 {
                let tc = response.toolCalls[0]
                return .toolCall(ToolExecutionRequest(
                    toolName: tc.name,
                    arguments: tc.arguments,
                    origin: origin,
                    sessionID: sessionID
                ))
            } else {
                let requests = response.toolCalls.map { tc in
                    ToolExecutionRequest(
                        toolName: tc.name,
                        arguments: tc.arguments,
                        origin: origin,
                        sessionID: sessionID
                    )
                }
                return .multipleToolCalls(requests)
            }
        }

        // 2. Only parse strict fallback JSON when in tool-call mode
        guard response.isToolCallMode else {
            return .assistantText(response.content)
        }

        // 3. Try to parse strict swoosh_tool_call JSON
        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("{") else {
            return .assistantText(response.content)
        }

        do {
            let payload = try StrictToolCallJSON.decode(text)
            return .toolCall(ToolExecutionRequest(
                toolName: payload.name,
                arguments: payload.arguments,
                origin: origin,
                sessionID: sessionID
            ))
        } catch {
            // If the JSON doesn't match our strict format, treat as text
            return .assistantText(response.content)
        }
    }
}
