// SwooshMacros/Macros.swift — Public macro declarations

import SwooshTools

/// Annotate a struct to automatically generate `SwooshTool` protocol conformance.
///
/// ```swift
/// @SwooshToolMacro(
///     name: "shell.run",
///     description: "Execute a shell command.",
///     permissions: [.shellRun],
///     risk: .high
/// )
/// struct ShellTool {
///     struct Input: Codable, Sendable {
///         let command: String
///         let workingDirectory: String?
///     }
///
///     func execute(_ input: Input, context: ToolContext) async throws -> JSONValue {
///         // ...
///     }
/// }
/// ```
@attached(member, names: named(name), named(description), named(permissions), named(risk), named(inputSchema), named(call))
@attached(extension, conformances: SwooshTool)
public macro SwooshToolMacro(
    name: String,
    description: String,
    permissions: [SwooshPermission] = [],
    risk: ToolRisk = .medium
) = #externalMacro(module: "SwooshMacroPlugin", type: "SwooshToolMacro")
