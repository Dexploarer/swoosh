// SwooshProviderBridge/ProviderBridgeAdapter.swift — SwooshProviders → SwooshCore adapter — 0.9B
//
// Adapts the real `ProviderRouter` to the `SwooshCore.ModelProvider`
// protocol so the daemon can mount the inference stack. Handles type
// conversion between `SwooshCore.ChatMessage` and `SwooshTools.ChatMessage`.
//
// The adapter is a value type (`struct`) because every stored field is
// `let` — earlier drafts wrapped this in `final class @unchecked Sendable`,
// which documented a non-existent soft spot. A struct satisfies `Sendable`
// straight from the compiler with no escape hatch.

import Foundation
import os
import SwooshCore
import SwooshProviders
import SwooshTools

/// Bridges the real `ProviderRouter` to `SwooshCore.ModelProvider`.
/// This is the integration point where Swoosh starts using real LLM inference.
public struct ProviderBridgeAdapter: SwooshCore.ModelProvider, Sendable {
    public let providerID: String = "provider-router"
    public let modelName: String

    private let router: ProviderRouter
    private let role: SwooshProviders.ModelRole
    private let defaultProviderID: String?

    public init(
        router: ProviderRouter,
        role: SwooshProviders.ModelRole = .primaryChat,
        modelName: String = "auto",
        defaultProviderID: String? = nil
    ) {
        self.router = router
        self.role = role
        self.modelName = modelName
        self.defaultProviderID = defaultProviderID
    }

    public func complete(
        _ request: SwooshCore.ModelCompletionRequest
    ) async throws -> SwooshCore.ModelCompletionResponse {
        let toolsMessages: [SwooshTools.ChatMessage] = request.messages.map { msg in
            SwooshTools.ChatMessage(
                role: Self.convertRole(msg.role),
                content: msg.content
            )
        }
        let routedProviderID = request.providerID ?? defaultProviderID
        let metadata = routedProviderID.map { ["providerID": $0] } ?? [:]
        let modelRequest = ModelRequest(
            model: request.model ?? modelName,
            messages: toolsMessages,
            tools: request.tools.map(Self.providerToolDescriptor),
            metadata: metadata
        )
        let response = try await router.complete(role: role, request: modelRequest)
        let toolCalls: [SwooshCore.NativeToolCall] = response.toolCalls.map { call in
            NativeToolCall(id: call.id, name: call.name, arguments: call.arguments)
        }
        let usage = SwooshCore.ModelUsage(
            promptTokens: response.usage?.promptTokens ?? 0,
            completionTokens: response.usage?.completionTokens ?? 0,
            totalTokens: response.usage?.totalTokens ?? 0
        )
        return SwooshCore.ModelCompletionResponse(
            content: response.text,
            model: response.model,
            usage: usage,
            toolCalls: toolCalls,
            isToolCallMode: !toolCalls.isEmpty
        )
    }

    /// Map `SwooshCore.ChatRole` (4 cases) to `SwooshTools.ChatRole`. The
    /// exhaustive switch trips the compiler if SwooshCore ever gains a
    /// new role — silent drift at the bridge boundary is the kind of bug
    /// that's hard to find later.
    static func convertRole(_ role: SwooshCore.ChatRole) -> SwooshTools.ChatRole {
        switch role {
        case .system: return .system
        case .user: return .user
        case .assistant: return .assistant
        case .tool: return .tool
        }
    }

    private static func providerToolDescriptor(
        _ descriptor: SwooshTools.ToolDescriptor
    ) -> SwooshProviders.ToolDescriptor {
        SwooshProviders.ToolDescriptor(
            name: descriptor.name,
            description: descriptor.description,
            inputSchema: descriptor.inputSchema.asJSONValue()
        )
    }
}

extension SwooshTools.JSONSchema {
    /// Re-encode the typed schema as the dynamic `JSONValue` shape that
    /// `SwooshProviders.ToolDescriptor` expects. The encoder + decoder
    /// are static so the round-trip doesn't allocate fresh ones per
    /// call; the previous form paid that cost on every tool of every
    /// request. Object-with-`type:object` is the inert fallback if
    /// encoding fails — failures log via `os_log` so silent shape
    /// drift doesn't go unnoticed.
    fileprivate func asJSONValue() -> SwooshTools.JSONValue {
        do {
            let data = try Self.schemaEncoder.encode(self)
            return try Self.schemaDecoder.decode(SwooshTools.JSONValue.self, from: data)
        } catch {
            Self.schemaLog.error(
                "JSONSchema → JSONValue conversion failed: \(String(describing: error), privacy: .public)"
            )
            return .object(["type": .string("object")])
        }
    }

    fileprivate static let schemaEncoder = JSONEncoder()
    fileprivate static let schemaDecoder = JSONDecoder()
    fileprivate static let schemaLog = Logger(
        subsystem: "ai.swoosh", category: "provider-bridge.schema"
    )
}
