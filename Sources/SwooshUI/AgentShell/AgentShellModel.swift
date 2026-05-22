// SwooshUI/AgentShell/AgentShellModel.swift — 0.9R Shared shell state
//
// One state object backs all three Mac host modes — tray popover, voice
// pill, and full window. The generative surface host is the canonical
// content area; the chat thread is the conversational tail; voice state
// tracks the mic pipeline.
//
// Lifetime: a single AgentShellModel lives at the app root and is passed
// into each host. There is exactly one chat session at a time across the
// three modes — switching modes never forks the conversation.

import Foundation
import SwooshGenerativeUI
import SwooshModels
import SwooshProviders

// ═══════════════════════════════════════════════════════════════════
// MARK: - Voice state
// ═══════════════════════════════════════════════════════════════════

public enum AgentVoiceState: String, Sendable, CaseIterable {
    /// Mic off. The pill shows the resting state.
    case idle
    /// Listening — STT is consuming audio. Pulse animation.
    case listening
    /// Audio captured, transcribing or waiting on model.
    case processing
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Chat thread
// ═══════════════════════════════════════════════════════════════════

public struct AgentShellMessage: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let role: Role
    public var text: String
    public let timestamp: Date

    public enum Role: String, Sendable, Codable { case user, agent }

    public init(id: UUID = UUID(), role: Role, text: String, timestamp: Date = .now) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Shell mode
// ═══════════════════════════════════════════════════════════════════

/// Which host the user is currently looking at. Affects density and
/// chrome, not behaviour — the same chat thread and surface host serve
/// every mode.
public enum AgentShellMode: Sendable, CaseIterable {
    case tray       // ~360pt popover from MenuBarExtra (macOS)
    case pill       // ~440×56 floating capsule (macOS)
    case window     // ~900pt main window with sidebar (macOS dashboard)
    case phone      // iPhone — fills width, respects safe areas, no minWidth clamp
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Send handler
// ═══════════════════════════════════════════════════════════════════

/// Plug a real agent backend in by setting `AgentShellModel.send`.
/// Default is a placeholder that echoes the message — keeps the UI
/// shippable before the kernel/daemon wire-up.
public typealias AgentSendHandler = @MainActor (String, AgentShellModel) async -> Void

// ═══════════════════════════════════════════════════════════════════
// MARK: - Model
// ═══════════════════════════════════════════════════════════════════

@MainActor
@Observable
public final class AgentShellModel {

    // ── Conversation ─────────────────────────────────────────────────

    public var messages: [AgentShellMessage] = []
    public var input: String = ""

    // ── Generative surface ───────────────────────────────────────────

    /// The agent emits typed UI into this host. Surfaces are keyed by id.
    /// The chat / pill / window all bind to the same host.
    public let surfaceHost: GenerativeSurfaceHost

    /// The active surface id rendered in the shell's content area. The
    /// agent can switch this via `UIAction.setSurface` and the host's
    /// `onSetSurface` handler — set up by `AgentShellModel.init`.
    public var activeSurfaceID: String = "main"

    // ── Model + reasoning selection ──────────────────────────────────

    public var selectedModelID: String
    public var selectedEffort: ReasoningEffort

    // ── Sync state ──────────────────────────────────────────────────

    /// Surfaced as a small badge in the input row. Default `.online`;
    /// flip to `.offline` or `.queued(n)` when sends fail or queue.
    public var syncState: SyncState = .online

    /// True while a `submit()` is in flight — surfaces as a "thinking"
    /// row at the end of the chat thread.
    public var isAwaitingResponse: Bool = false

    // ── Voice ────────────────────────────────────────────────────────

    public var voice: AgentVoiceState = .idle

    /// Whether the pill is currently expanded into its content panel.
    /// Resets to false when the pill closes or when voice goes idle.
    public var isPillExpanded: Bool = false

    /// Live STT pipeline. `SpeechCapture` is its own `@Observable`, so
    /// views can `@Bindable shell.speech` to read its live transcript +
    /// audio level without round-tripping through the shell.
    @ObservationIgnored
    public let speech: SpeechCapture = SpeechCapture()

    // ── Send pipeline ────────────────────────────────────────────────

    /// Replace at the app root to wire a real backend. Default echoes.
    public var send: AgentSendHandler = AgentShellModel.defaultEcho

    // ── Init ─────────────────────────────────────────────────────────

    public init(
        surfaceHost: GenerativeSurfaceHost = GenerativeSurfaceHost(),
        selectedModelID: String = ModelDefaults.defaultInteractiveModelID,
        selectedEffort: ReasoningEffort = .extraHigh
    ) {
        self.surfaceHost = surfaceHost
        self.selectedModelID = selectedModelID
        self.selectedEffort = selectedEffort

        // Wire surface-switch action to the local state so the agent can
        // navigate the shell by emitting a setSurface action.
        surfaceHost.onSetSurface = { [weak self] id, _ in
            self?.activeSurfaceID = id
        }
    }

    // ── Actions ──────────────────────────────────────────────────────

    /// Send whatever's in `input` and clear the field.
    public func submit() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isAwaitingResponse else { return }
        input = ""
        messages.append(.init(role: .user, text: text))
        isAwaitingResponse = true
        await send(text, self)
        isAwaitingResponse = false
    }

    public func startListening() {
        voice = .listening
        isPillExpanded = true
        speech.start()
    }

    /// Stop the audio capture. If `commit` is true (the default), the
    /// finalized transcript is dropped into `input` so the user can review
    /// before submitting; pass false to discard.
    public func stopListening(commit: Bool = true) {
        speech.stop()
        if commit, !speech.transcript.isEmpty {
            input = input.isEmpty
                ? speech.transcript
                : "\(input) \(speech.transcript)"
        }
        voice = .idle
    }

    public func clearConversation() {
        messages.removeAll()
        input = ""
        voice = .idle
        isPillExpanded = false
    }

    // ── Default handler (echo) ───────────────────────────────────────

    private static let defaultEcho: AgentSendHandler = { text, shell in
        // Placeholder until the kernel/daemon wire-up replaces `send`.
        // Speaks in Detour's voice so the persona is consistent even
        // before a real provider is connected.
        try? await Task.sleep(nanoseconds: 200_000_000)
        shell.messages.append(.init(
            role: .agent,
            text: "Detour (placeholder): \(text)"
        ))
    }
}
