// SwooshUI/GenerativeSurfaces/GenerativeSurfaceHost.swift — Bridge to SwooshGenerativeUI (0.4A)
//
// Bridges `SwooshGenerativeUI` into the dashboard. Holds the active surfaces
// per route (chat-detail, inspector, modal), routes `UIAction`s to host
// handlers (tool calls, surface switches, approve/deny), and updates
// surfaces incrementally as the agent streams them.

import SwiftUI
import SwooshGenerativeUI

// MARK: - Host actor

@Observable
public final class GenerativeSurfaceHost {
    /// Active surfaces keyed by `surfaceID`.
    public private(set) var surfaces: [String: UISurfaceUpdate] = [:]
    public var defaultCatalog: ComponentCatalog
    public var onToolCall: (@MainActor (String, [String: UIScalar]) -> Void)?
    public var onIntent:   (@MainActor (String, [String: UIScalar]) -> Void)?
    public var onApproval: (@MainActor (_ toolCallID: String, _ approve: Bool, _ scopeOrReason: String) -> Void)?
    public var onOpenURL:  (@MainActor (URL) -> Void)?
    public var onSetSurface: (@MainActor (_ id: String, _ payload: [String: UIScalar]) -> Void)?

    public init(catalog: ComponentCatalog = .standard) {
        self.defaultCatalog = catalog
    }

    /// Replace (or insert) a surface. Increments version automatically.
    public func apply(_ surface: UISurfaceUpdate) {
        var updated = surface
        if let existing = surfaces[surface.surfaceID] {
            updated.version = max(existing.version + 1, surface.version)
        }
        surfaces[surface.surfaceID] = updated
    }

    /// Clear a surface (e.g. on dismiss).
    public func clear(surfaceID: String) {
        surfaces.removeValue(forKey: surfaceID)
    }

    /// Handler for `UIAction`s emitted by rendered components.
    @MainActor
    public func handle(_ action: SwooshGenerativeUI.UIAction, context: SwooshGenerativeUI.UIActionContext) {
        switch action {
        case let .toolCall(name, arguments):
            onToolCall?(name, arguments)
        case let .openURL(string):
            if let url = URL(string: string) { onOpenURL?(url) }
        case let .dispatchIntent(name, payload):
            onIntent?(name, payload)
        case let .setSurface(id, payload):
            onSetSurface?(id, payload)
        case let .approve(toolCallID, scope):
            onApproval?(toolCallID, true, scope)
        case let .deny(toolCallID, reason):
            onApproval?(toolCallID, false, reason)
        case .noop:
            break
        }
    }
}

// MARK: - Renderer view

public struct GenerativeSurfaceView: View {
    @Bindable public var host: GenerativeSurfaceHost
    public let surfaceID: String
    public let catalog: ComponentCatalog?

    public init(host: GenerativeSurfaceHost, surfaceID: String, catalog: ComponentCatalog? = nil) {
        self.host = host
        self.surfaceID = surfaceID
        self.catalog = catalog
    }

    public var body: some View {
        if let surface = host.surfaces[surfaceID] {
            UIRenderer(
                surface: surface,
                catalog: catalog ?? host.defaultCatalog
            ) { action, ctx in
                Task { @MainActor in
                    host.handle(action, context: ctx)
                }
            }
            .id(surface.version)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                Text("Waiting for surface '\(surfaceID)'")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
