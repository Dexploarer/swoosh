// SwooshUI/Themes/SymbolEffects.swift — SF Symbol motion helpers (0.4A)
//
// Wraps the SwiftUI `.symbolEffect(...)` family in named modifiers tuned for
// Swoosh surfaces: pulsing on active state, variable-color iteration during
// refresh, breathe for ambient idle, bounce on value change. The wrappers
// degrade cleanly on older OSes — the call site doesn't need any availability
// checks.

import SwiftUI

// MARK: - Pulse while active

public struct SwooshPulseModifier: ViewModifier {
    let isActive: Bool

    public func body(content: Content) -> some View {
        content.symbolEffect(.pulse, options: .repeating, isActive: isActive)
    }
}

// MARK: - Variable color iteration (e.g. while loading)

public struct SwooshVariableColorModifier: ViewModifier {
    let isActive: Bool

    public func body(content: Content) -> some View {
        content.symbolEffect(
            .variableColor.iterative.reversing,
            options: .repeating,
            isActive: isActive
        )
    }
}

// MARK: - Breathe (ambient, macOS 26+)

public struct SwooshBreatheModifier: ViewModifier {
    let isActive: Bool

    public func body(content: Content) -> some View {
        if #available(macOS 15.0, iOS 18.0, *) {
            content.symbolEffect(.breathe, options: .repeating, isActive: isActive)
        } else {
            content.symbolEffect(.pulse, options: .repeating, isActive: isActive)
        }
    }
}

// MARK: - Bounce when a value changes

public struct SwooshBounceOnChangeModifier<V: Equatable>: ViewModifier {
    let value: V

    public func body(content: Content) -> some View {
        content.symbolEffect(.bounce, value: value)
    }
}

// MARK: - View extensions

public extension View {
    /// Repeating pulse while `isActive` is true. Best for "this is happening
    /// right now" indicators (an agent run, a refresh in flight).
    func swooshPulse(_ isActive: Bool = true) -> some View {
        modifier(SwooshPulseModifier(isActive: isActive))
    }

    /// Iterative variable-color animation while `isActive`. Suits multi-state
    /// loaders and live meters where the user benefits from a sense of flow.
    func swooshVariableColor(_ isActive: Bool = true) -> some View {
        modifier(SwooshVariableColorModifier(isActive: isActive))
    }

    /// Ambient breathing motion. Subtle — use on hero/status icons that
    /// should feel alive without grabbing attention.
    func swooshBreathe(_ isActive: Bool = true) -> some View {
        modifier(SwooshBreatheModifier(isActive: isActive))
    }

    /// One-shot bounce whenever `value` changes. Pair with selection state to
    /// add a tactile "you picked this" cue.
    func swooshBounceOnChange<V: Equatable>(_ value: V) -> some View {
        modifier(SwooshBounceOnChangeModifier(value: value))
    }
}

// MARK: - Sensory feedback shortcut

public extension View {
    /// Trigger a system sensory-feedback haptic/sound when `value` changes.
    /// Defaults to `.success`. Wraps `.sensoryFeedback` so call sites stay terse.
    func swooshFeedback<V: Equatable>(
        _ feedback: SensoryFeedback = .success,
        on value: V
    ) -> some View {
        sensoryFeedback(feedback, trigger: value)
    }
}
