// SwooshMacroPlugin/SwooshToolMacro.swift — @SwooshTool macro
//
// Compile-time tool contract generation.
// Typed. Permissioned. Schema auto-generated.

import SwiftSyntax
import SwiftSyntaxMacros
import SwiftCompilerPlugin

// MARK: - Macro declaration (used from SwooshMacros)

/// The `@SwooshTool` macro generates the `Tool` protocol conformance,
/// including `name`, `description`, `inputSchema`, `permissions`, and `risk`.
///
/// Usage:
/// ```swift
/// @SwooshTool(
///     name: "file.read",
///     description: "Read the contents of a file.",
///     permissions: [.filesystemRead],
///     risk: .low
/// )
/// struct FileReadTool {
///     struct Input: Codable, Sendable {
///         let path: String
///         let encoding: String?
///     }
///
///     func execute(_ input: Input, context: ToolContext) async throws -> ToolResult {
///         let data = try Data(contentsOf: URL(fileURLWithPath: input.path))
///         let text = String(data: data, encoding: .utf8) ?? ""
///         return .success(text)
///     }
/// }
/// ```
public struct SwooshToolMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Extract arguments from @SwooshTool(name: ..., description: ..., permissions: [...], risk: ...)
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else {
            return []
        }

        var name = "\"unnamed\""
        var description = "\"\""
        var permissions = "[]"
        var risk = ".medium"

        for arg in arguments {
            let label = arg.label?.text ?? ""
            let value = arg.expression.description.trimmingCharacters(in: .whitespacesAndNewlines)
            switch label {
            case "name":        name = value
            case "description": description = value
            case "permissions": permissions = value
            case "risk":        risk = value
            default: break
            }
        }

        return [
            "public static var name: String { \(raw: name) }",
            "public static var description: String { \(raw: description) }",
            "public static var permissions: [SwooshPermission] { \(raw: permissions) }",
            "public static var risk: ToolRisk { \(raw: risk) }",
            """
            public static var inputSchema: JSONSchema {
                JSONSchema(type: "object", description: \(raw: description))
            }
            """,
            """
            public func call(_ input: JSONValue, context: ToolContext) async throws -> JSONValue {
                // Decode input and delegate to execute method
                let data = try JSONEncoder().encode(input)
                let decoded = try JSONDecoder().decode(Input.self, from: data)
                return try await execute(decoded, context: context)
            }
            """
        ]
    }
}

// MARK: - Extension macro for Tool conformance

public struct SwooshToolExtensionMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        let ext: DeclSyntax = "extension \(type.trimmed): SwooshTool {}"
        return [ext.cast(ExtensionDeclSyntax.self)]
    }
}

// MARK: - Plugin registration

@main
struct SwooshMacroPluginEntry: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        SwooshToolMacro.self,
        SwooshToolExtensionMacro.self,
    ]
}
