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
    @State private var isSending: Bool = false
    @State private var errorText: String?
    @FocusState private var inputFocused: Bool

    var body: some View {
        Group {
            if session.isPaired {
                paired
            } else {
                unpaired
            }
        }
    }

    // MARK: - Paired conversation

    private var paired: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
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
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
    }

    private var unpaired: some View {
        ContentUnavailableView {
            Label("Not paired", systemImage: "link.badge.plus")
        } description: {
            Text("Open Settings, point Swoosh at swooshd on your Mac, and paste the bearer token printed in its startup log.")
        }
    }

    // MARK: - Sending

    private func send() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
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
                    ChatRequest(sessionID: "ios-default", input: trimmed)
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
    let id: UUID = UUID()
    let role: Role
    let text: String
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
