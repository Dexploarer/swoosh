#if os(iOS)

// SwooshLocalLLM/LiteRTSwooshToolBridge.swift — 0.9R Bridge Swoosh tools to LiteRT
//
// LiteRT-LM expects each tool as a Swift type conforming to `Tool` with
// `@ToolParam`-annotated properties. Swoosh's `SwooshTool` registry is
// runtime-typed with `Codable` `Input` / `Output` structs — incompatible
// shapes.
//
// This bridge exposes ONE LiteRT-side tool — `SwooshDispatchTool` —
// that the on-device model can call with `{name: "<toolID>", args:
// "<json>"}`. Internally it routes to Swoosh's `ToolRegistry`, which
// runs the call through `SwooshFirewall` (same gating as the cloud
// path) and returns the JSON output.
//
// This keeps the firewall + audit + humanOnly invariants intact when
// the local LiteRT model picks a tool — the model can't bypass the
// permission system just because it's running offline.

import Foundation
import LiteRTLM

/// LiteRT-side meta-tool. The local model invokes this with a tool
/// name + JSON args; we route through the Swoosh registry.
///
/// Wire by:
///   1. Register a dispatch handler at app start:
///      `SwooshDispatchTool.dispatch = { name, jsonArgs in ... }`
///   2. Pass `SwooshDispatchTool.self` in `LiteRTEngineWrapper.load(tools:)`
///   3. The local model can now emit `swoosh_dispatch(name:"...", args:"...")`
public class SwooshDispatchTool: Tool {

    public static var name: String { "swoosh_dispatch" }
    public static var description: String {
        """
        Invoke any registered Swoosh tool. Pass the tool's name and a
        JSON-encoded arguments string. The result returns as a JSON
        string. Use this for filesystem, network, crypto, browser,
        skill, and any other capability the host registered.
        """
    }

    @ToolParam(description: "The name of the Swoosh tool to invoke (e.g. 'fs_read', 'solana_balance').")
    public var name: String = ""

    @ToolParam(description: "JSON string with the tool's arguments. Use {} if there are none.")
    public var args: String = "{}"

    public required init() {}

    public func run() async throws -> Any {
        guard let dispatch = SwooshDispatchTool.dispatch else {
            return ["error": "No Swoosh dispatch handler registered."]
        }
        do {
            let jsonString = try await dispatch(name, args)
            // Dispatcher returns a JSON-serialized string. Parse it so the
            // model receives a structured object — otherwise the response
            // arrives as a string-of-JSON and the model has to unwrap it.
            if let data = jsonString.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) {
                return parsed
            }
            return ["result": jsonString]
        } catch {
            return ["error": String(describing: error)]
        }
    }

    /// Set this at app start with a closure that routes (toolName, jsonArgs)
    /// through Swoosh's ToolRegistry. The closure must apply the same
    /// firewall + approval gates as the cloud path — humanOnly tools
    /// must NOT execute without a real user grant.
    public nonisolated(unsafe) static var dispatch: (@Sendable (String, String) async throws -> String)? = nil
}

#endif
