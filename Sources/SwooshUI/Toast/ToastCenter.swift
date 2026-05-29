// SwooshUI/Toast/ToastCenter.swift — Lightweight in-app toast notifications — 0.9Y
//
// A small observable toast queue + host overlay. Created so the agent can
// surface actionable prompts (e.g. "N memories to review") with an explicit
// button, per product direction — rather than burying review behind a tab.
// Hosted on the dashboard window via `.toastHost(_:)`. One toast at a time;
// `dedupeKey` stops the same prompt re-appearing on every poll.

#if os(macOS)
import SwiftUI
import SwooshGenerativeUI

@MainActor
@Observable
public final class ToastCenter {
    public struct Action: Identifiable {
        public let id = UUID()
        public let label: String
        public let prominent: Bool
        public let handler: () -> Void
        public init(_ label: String, prominent: Bool = false, handler: @escaping () -> Void) {
            self.label = label
            self.prominent = prominent
            self.handler = handler
        }
    }

    public struct Toast: Identifiable {
        public let id = UUID()
        public let icon: String
        public let title: String
        public let message: String?
        public let actions: [Action]
        public let dedupeKey: String?
    }

    public private(set) var current: Toast?
    private var shownKeys: Set<String> = []

    public init() {}

    public func show(
        icon: String,
        title: String,
        message: String? = nil,
        actions: [Action] = [],
        dedupeKey: String? = nil
    ) {
        if let key = dedupeKey {
            guard !shownKeys.contains(key) else { return }
            shownKeys.insert(key)
        }
        current = Toast(icon: icon, title: title, message: message, actions: actions, dedupeKey: dedupeKey)
    }

    public func dismiss() { current = nil }

    /// Allow a deduped prompt to be shown again (e.g. after the underlying
    /// state changes and a fresh prompt is warranted).
    public func resetDedupe(_ key: String) { shownKeys.remove(key) }
}

// MARK: - Host

public struct ToastHostModifier: ViewModifier {
    let center: ToastCenter

    public func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toast = center.current {
                    ToastView(toast: toast, onDismiss: { center.dismiss() })
                        .padding(20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: center.current?.id)
    }
}

public extension View {
    func toastHost(_ center: ToastCenter) -> some View {
        modifier(ToastHostModifier(center: center))
    }
}

// MARK: - Toast view

struct ToastView: View {
    let toast: ToastCenter.Toast
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: toast.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(VoltPaper.accent)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(toast.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(VoltPaper.foreground)
                if let message = toast.message {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(VoltPaper.mutedFg)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                ForEach(toast.actions) { action in
                    Button {
                        action.handler()
                        onDismiss()
                    } label: {
                        Text(action.label)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(action.prominent ? VoltPaper.accentFg : VoltPaper.foreground)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(action.prominent ? VoltPaper.accent : VoltPaper.foreground.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(VoltPaper.mutedFg)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 460)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(VoltPaper.surface)
                .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(VoltPaper.border, lineWidth: 0.5)
        )
    }
}

#endif
