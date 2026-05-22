// SwooshUI/AgentShell/GlobalHotKey.swift — 0.9R System-wide hotkey
//
// Carbon RegisterEventHotKey wrapper. SwiftUI's `.keyboardShortcut` is
// app-scoped — only fires when the menu-bar app is the focused responder.
// Voice-pill summoning has to work from any app, so we drop down to the
// Carbon API. This is still the canonical way to do it on macOS 26.
//
// Usage:
//   let hk = GlobalHotKey(key: .space, modifiers: [.option]) {
//       NotificationCenter.default.post(name: .swooshShowVoicePill, object: nil)
//   }
//   // Keep `hk` alive (e.g. as @State at App root). Deinit unregisters.

#if os(macOS)

import Foundation
import AppKit
import Carbon.HIToolbox

// ═══════════════════════════════════════════════════════════════════
// MARK: - Public model
// ═══════════════════════════════════════════════════════════════════

public struct GlobalHotKeyModifiers: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let command: GlobalHotKeyModifiers = .init(rawValue: UInt32(cmdKey))
    public static let option:  GlobalHotKeyModifiers = .init(rawValue: UInt32(optionKey))
    public static let control: GlobalHotKeyModifiers = .init(rawValue: UInt32(controlKey))
    public static let shift:   GlobalHotKeyModifiers = .init(rawValue: UInt32(shiftKey))
}

public enum GlobalHotKeyCode: UInt32, Sendable {
    case space  = 0x31  // kVK_Space
    case period = 0x2F
    case slash  = 0x2C
    case escape = 0x35
    case backtick = 0x32

    case k1 = 0x12, k2 = 0x13, k3 = 0x14, k4 = 0x15, k5 = 0x17
    case k6 = 0x16, k7 = 0x1A, k8 = 0x1C, k9 = 0x19, k0 = 0x1D
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Hotkey
// ═══════════════════════════════════════════════════════════════════

/// A single registered global hotkey. Lifetime-managed — keep a strong
/// reference (e.g. `@State`) for the binding to remain active. The
/// destructor unregisters automatically.
public final class GlobalHotKey: @unchecked Sendable {

    private let signature: OSType = OSType(0x53575348)  // 'SWSH'
    fileprivate let id: UInt32
    private var ref: EventHotKeyRef?
    private let handler: @Sendable () -> Void

    public init(key: GlobalHotKeyCode,
                modifiers: GlobalHotKeyModifiers,
                handler: @escaping @Sendable () -> Void) {
        self.id = GlobalHotKeyRegistry.shared.nextID()
        self.handler = handler
        GlobalHotKeyRegistry.shared.register(self)

        let hkID = EventHotKeyID(signature: signature, id: id)
        var hkRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            key.rawValue,
            modifiers.rawValue,
            hkID,
            GetEventDispatcherTarget(),
            0,
            &hkRef
        )
        if status == noErr {
            self.ref = hkRef
        }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        GlobalHotKeyRegistry.shared.unregister(id: id)
    }

    fileprivate func fire() {
        handler()
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Registry + Carbon event handler
// ═══════════════════════════════════════════════════════════════════

private final class GlobalHotKeyRegistry: @unchecked Sendable {
    static let shared = GlobalHotKeyRegistry()

    private let queue = DispatchQueue(label: "ai.swoosh.globalhotkey")
    private var hotkeys: [UInt32: GlobalHotKey] = [:]
    private var nextRawID: UInt32 = 0
    private var handlerInstalled = false

    func nextID() -> UInt32 {
        queue.sync {
            nextRawID += 1
            return nextRawID
        }
    }

    func register(_ hk: GlobalHotKey) {
        queue.sync {
            hotkeys[hk.id] = hk
            if !handlerInstalled {
                installHandler()
                handlerInstalled = true
            }
        }
    }

    func unregister(id: UInt32) {
        queue.sync {
            _ = hotkeys.removeValue(forKey: id)
        }
    }

    fileprivate func dispatch(id: UInt32) {
        // Hop to main — UI work runs there.
        DispatchQueue.main.async {
            self.queue.sync { self.hotkeys[id] }?.fire()
        }
    }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, _ in
                var hkID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                if status == noErr {
                    GlobalHotKeyRegistry.shared.dispatch(id: hkID.id)
                }
                return noErr
            },
            1,
            &spec,
            nil,
            nil
        )
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Notification names
// ═══════════════════════════════════════════════════════════════════

public extension Notification.Name {
    static let swooshShowVoicePill = Notification.Name("ai.swoosh.showVoicePill")
    static let swooshHideVoicePill = Notification.Name("ai.swoosh.hideVoicePill")
}

#endif
