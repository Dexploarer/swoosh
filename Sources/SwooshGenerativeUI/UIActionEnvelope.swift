// SwooshGenerativeUI/UIActionEnvelope.swift — Outbound action wiring (0.4A)
//
// When a rendered component fires a `UIAction`, the renderer hands it off to
// a typed handler. The host installs the handler at render time and decides
// what each action means (call a tool, switch surfaces, open a URL, …).

import Foundation

/// Function signature for action handlers. Receives the action, the surface
/// it originated from, and the component ID that fired it.
public typealias UIActionHandler = @MainActor @Sendable (UIAction, UIActionContext) -> Void

/// Contextual info passed to every action handler.
public struct UIActionContext: Sendable {
    public let surfaceID: String
    public let componentID: String
    public let timestamp: Date

    public init(surfaceID: String, componentID: String, timestamp: Date = Date()) {
        self.surfaceID = surfaceID
        self.componentID = componentID
        self.timestamp = timestamp
    }
}

/// Reusable no-op handler — useful in previews and tests.
public let uiActionHandlerNoop: UIActionHandler = { _, _ in }
