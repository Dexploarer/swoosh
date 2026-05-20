// Apps/SwooshiOS/ChatView.swift — Single-conversation chat surface
//
// Pure SwiftUI list of message bubbles, an input field, and a send button.
// Every send posts to `POST /api/agent/chat` on swooshd. Streaming is a
// future addition; for now the UI shows a spinner while the daemon
// finishes the turn and then appends the full assistant reply.

import SwiftUI
import SwooshClient

struct ChatView: View {
    @Environment(ClientSession.self) private var session
    @State private var draft: String = ""
    @State private var messages: [Message] = []
    @State private var isLoadingTranscript: Bool = false
    @State private var isSending: Bool = false
    @State private var errorText: String?
    @State private var loadedTranscriptKey: String?
    @FocusState private var inputFocused: Bool

    var body: some View {
        Group {
            if session.isPaired {
                paired
            } else {
                unpaired
            }
        }
        .task(id: transcriptKey) {
            await loadTranscript()
        }
    }

    // MARK: - Paired conversation

    private var paired: some View {
        VStack(spacing: 0) {
            if isDiagnosticProvider {
                ProviderWarningBanner()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if isLoadingTranscript && messages.isEmpty {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Loading conversation…").foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                        }
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                        if isSending {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Thinking…").foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 16)
                }
                .onChange(of: messages.count) {
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            if let errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }

            HStack(spacing: 8) {
                TextField("Message Swoosh", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit(send)
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending || isLoadingTranscript)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
    }

    private var isDiagnosticProvider: Bool {
        session.agentStatus?.model == "swoosh-local-diagnostic-v1"
    }

    private var unpaired: some View {
        ContentUnavailableView {
            Label("Not paired", systemImage: "link.badge.plus")
        } description: {
            Text("Open Settings, point Swoosh at swooshd on your Mac, and paste the bearer token printed in its startup log.")
        }
    }

    // MARK: - Transcript

    private var transcriptKey: String? {
        session.host.map { "\($0.absoluteString)#\(session.sessionID)" }
    }

    private func loadTranscript() async {
        guard session.isPaired, let client = session.client(), let transcriptKey else {
            messages = []
            loadedTranscriptKey = nil
            return
        }
        guard loadedTranscriptKey != transcriptKey else { return }

        isLoadingTranscript = true
        errorText = nil
        defer { isLoadingTranscript = false }

        do {
            let transcript = try await client.transcript(sessionID: session.sessionID)
            messages = transcript.messages.compactMap(Message.init)
            loadedTranscriptKey = transcriptKey
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: - Sending

    private func send() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending, !isLoadingTranscript else { return }
        guard let executor = session.executor() else {
            errorText = "Not paired with a daemon."
            return
        }
        let userMessage = Message(role: .user, text: trimmed)
        messages.append(userMessage)
        draft = ""
        isSending = true
        errorText = nil

        Task {
            defer { isSending = false }
            do {
                let response = try await executor.run(
                    ChatRequest(sessionID: session.sessionID, input: trimmed)
                )
                messages.append(Message(role: .agent, text: response.message))
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}

// MARK: - Message model + bubble

struct Message: Identifiable, Equatable, Sendable {
    enum Role: Sendable { case user, agent }
    let id: String
    let role: Role
    let text: String

    init(id: String = UUID().uuidString, role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }

    init?(_ message: TranscriptMessage) {
        switch message.role {
        case .user:
            self.init(id: message.id, role: .user, text: message.content)
        case .assistant:
            self.init(id: message.id, role: .agent, text: message.content)
        case .system, .tool:
            return nil
        }
    }
}

private struct ProviderWarningBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text("Mac daemon is connected, but no model provider is active. Replies are diagnostic until you save a provider key in Control and restart swooshd.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }
}

private struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 32) }
            Text(message.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(foreground)
            if message.role == .agent { Spacer(minLength: 32) }
        }
        .padding(.horizontal)
    }

    private var background: some ShapeStyle {
        message.role == .user ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.thinMaterial)
    }

    private var foreground: Color {
        message.role == .user ? .white : .primary
    }
}
