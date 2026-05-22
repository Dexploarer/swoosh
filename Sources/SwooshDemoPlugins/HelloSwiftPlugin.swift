// SwooshDemoPlugins/HelloSwiftPlugin.swift — 0.8B Reference Swift Plugin
//
// `HelloSwiftPlugin` is the minimal end-to-end demo of the Swift plugin
// contract: it pairs with `Plugins/HelloSwift/manifest.json`, declares no
// permissions beyond `toolRead`, exposes one tool (`hello.echo`), and ships
// no side effects. It exists for two reasons:
//
//   1. Authors who want to write their own Swift plugin can copy this file
//      and the manifest as a starting point. Both pieces are small enough
//      to fit in a head.
//   2. The daemon registers it at startup so the swooshd integration test
//      has a real end-to-end path (manifest on disk → kernel call →
//      executor → AnySwooshTool output) instead of a mock.
//
// Phase 1 only ships the Swift kind. The executable / wasm demos arrive in
// the follow-on phases that flesh out those executors.

import Foundation
import SwooshPlugins
import SwooshTools

public struct HelloSwiftPlugin: SwiftPluginEntrypoint {
    public static let pluginID: String = "hello-swift"

    public init() {}

    public func call(
        toolName: String,
        args: JSONValue,
        context: ToolContext
    ) async throws -> JSONValue {
        switch toolName {
        case "hello.echo":
            let message: String = {
                if case .object(let dict) = args, case .string(let m) = dict["message"] {
                    return m
                }
                return ""
            }()
            return .object([
                "echoed": .string(message),
                "pluginID": .string(Self.pluginID),
                "sessionID": .string(context.sessionID),
            ])
        default:
            throw PluginError.toolNotRegistered("hello-swift/\(toolName)")
        }
    }
}
