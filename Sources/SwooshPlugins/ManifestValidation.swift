// SwooshPlugins/ManifestValidation.swift — 0.8B Manifest Validation
//
// Validation runs at install time (before the user is asked to approve the
// plugin) and again at every load. Failing validation means the plugin
// stays in the registry as a disabled entry — the user can inspect what
// went wrong and either install a corrected manifest or remove it.

import Foundation
import SwooshTools

extension PluginManifest {
    /// Validate the manifest against the typed permission model. Returns a
    /// list of validation errors; the manifest is considered valid iff this
    /// list is empty. Callers should refuse to enable any plugin with one or
    /// more validation errors.
    public func validate() -> [PluginValidationError] {
        var errors: [PluginValidationError] = []

        if id.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append(.emptyID)
        }
        // ID is used as a directory name under `~/.swoosh/plugins/` —
        // anything outside `[a-z0-9_-]` is a path-traversal vector. The
        // store and the host both `copyItem` / `removeItem` at
        // `<root>/<id>/…`, so an `id` of `"../escape"` would let an
        // authenticated install/uninstall caller write or delete outside
        // the plugins root. Validate at install time and refuse.
        if !id.isEmpty && id.unicodeScalars.contains(where: { !Self.allowedIDScalars.contains($0) }) {
            errors.append(.invalidID(id))
        }
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append(.emptyName)
        }
        if version.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append(.emptyVersion)
        }

        // Every requested permission must parse to a real `SwooshPermission`.
        // Plugins extend tools, not the permission system — a plugin that
        // requests `"banana"` is malformed, not "asking for a new perm".
        var requestedTyped: Set<SwooshPermission> = []
        for raw in requestedPermissions {
            guard let typed = SwooshPermission(rawValue: raw) else {
                errors.append(.unknownPermission(raw))
                continue
            }
            requestedTyped.insert(typed)
        }

        // Plugin admin permissions are humanOnly daemon-level operations,
        // not capabilities a plugin can request for itself. Refuse any
        // manifest that lists them, otherwise a malicious plugin could grant
        // itself the right to install other plugins on enable.
        for adminPerm in PluginManifest.reservedAdminPermissions {
            if requestedTyped.contains(adminPerm) {
                errors.append(.reservedAdminPermission(adminPerm.rawValue))
            }
        }

        // Each tool's permission must be one the plugin actually requested.
        // We hand the user a single list of capabilities to approve; tools
        // can't reach outside that list at call time.
        var seenToolNames: Set<String> = []
        for tool in tools {
            if tool.name.trimmingCharacters(in: .whitespaces).isEmpty {
                errors.append(.emptyToolName(toolID: tool.id))
            }
            if !seenToolNames.insert(tool.name).inserted {
                errors.append(.duplicateToolName(tool.name))
            }
            if !requestedTyped.contains(tool.permission) {
                errors.append(.toolPermissionNotRequested(
                    toolName: tool.name,
                    permission: tool.permission.rawValue
                ))
            }
        }

        // Entrypoint must match the kind. The `wasm` kind accepts both
        // the linear-memory `.wasm` and WASI `.wasiWasm` variants — they
        // pick different ABIs in the executor but ship the same module
        // shape (a `.wasm`/`.wat` file under the plugin dir).
        let entrypointMatch: Bool
        switch (kind, entrypoint) {
        case (.swift, .swiftModule), (.executable, .executable),
             (.wasm, .wasm), (.wasm, .wasiWasm),
             (.mcpBridge, .mcpServer):
            entrypointMatch = true
        default:
            entrypointMatch = false
        }
        if !entrypointMatch {
            errors.append(.entrypointKindMismatch(
                kind: kind.rawValue,
                entrypoint: String(describing: entrypoint)
            ))
        }

        return errors
    }

    /// Permissions a plugin manifest is forbidden from requesting. These
    /// gate the plugin lifecycle itself and are reserved for humanOnly
    /// admin calls into the daemon.
    public static let reservedAdminPermissions: Set<SwooshPermission> = [
        .pluginInstall, .pluginUninstall, .pluginEnable, .pluginDisable,
    ]

    /// Characters allowed in a plugin ID. Restricted to a strict
    /// path-safe set so the store/host can safely build filesystem paths
    /// as `<root>/<id>/…` — every other character (slash, dot, space,
    /// etc.) is a potential path-traversal or shell-quoting vector.
    static let allowedIDScalars: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "abcdefghijklmnopqrstuvwxyz")
        set.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        set.insert(charactersIn: "0123456789")
        set.insert(charactersIn: "-_")
        return set
    }()
}

public enum PluginValidationError: Error, Sendable, Equatable, CustomStringConvertible {
    case emptyID
    case invalidID(String)
    case emptyName
    case emptyVersion
    case unknownPermission(String)
    case reservedAdminPermission(String)
    case emptyToolName(toolID: String)
    case duplicateToolName(String)
    case toolPermissionNotRequested(toolName: String, permission: String)
    case entrypointKindMismatch(kind: String, entrypoint: String)

    public var description: String {
        switch self {
        case .emptyID: return "manifest id is empty"
        case .invalidID(let id): return "manifest id contains characters outside [A-Za-z0-9_-]: \(id)"
        case .emptyName: return "manifest name is empty"
        case .emptyVersion: return "manifest version is empty"
        case .unknownPermission(let p): return "unknown permission: \(p)"
        case .reservedAdminPermission(let p): return "plugin may not request reserved admin permission: \(p)"
        case .emptyToolName(let id): return "tool \(id) has an empty name"
        case .duplicateToolName(let n): return "duplicate tool name: \(n)"
        case .toolPermissionNotRequested(let tool, let perm):
            return "tool \(tool) requires permission \(perm) but the plugin did not request it"
        case .entrypointKindMismatch(let kind, let ep):
            return "entrypoint \(ep) does not match plugin kind \(kind)"
        }
    }
}
