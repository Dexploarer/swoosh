// Apps/SwooshiOS/ChatScreen.swift — Claude-mobile-style chat
//
// One screen, three states:
//   • empty            — large greeting + a few quick-prompt chips
//   • thread (paired)  — flat message stream with the composer pinned
//                        to the bottom
//   • unpaired         — explicit prompt to open Settings → pair
//
// Visual treatment matches Claude's iOS app: no bottom tab bar, no
// bubbles around the assistant text (only the user's turn is a bubble),
// composer is a rounded capsule with attach + send affordances. The model
// picker in the top bar is a placeholder until /api/agent/status returns
// a proper provider list — wired today to whatever provider swooshd reports.

import SwiftUI
import SwooshClient

private let suggestedPrompts: [String] = [
    "Summarize what I asked you last week",
    "What can you do with my Solana balance?",
    "Draft a Swift snippet to fetch ETH gas",
    "Review the last commit on the repo"
]

struct ChatScreen: View {
    @Environment(ClientSession.self) private var session
    @State private var draft: String = ""
    @State private var messages: [ChatBubble] = []
    @State private var isLoadingTranscript: Bool = false
    @State private var isSending: Bool = false
    /// The failed operation, if any — drives the retry affordance.
    @State private var failure: ChatFailure?
    @State private var loadedTranscriptKey: String?
    /// Last user input — kept so a failed send can be retried verbatim.
    @State private var lastSentText: String?
    @State private var sendFeedback: Int = 0
    @State private var errorFeedback: Int = 0
    @FocusState private var inputFocused: Bool

    let onOpenDrawer: () -> Void

    /// What failed, so the Retry button knows what to re-run.
    private enum ChatFailure: Equatable {
        case load(String)
        case send(String)
        var message: String {
            switch self {
            case .load(let m), .send(let m): return m
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ChatTopBar(
                model: session.agentStatus?.model,
                paired: session.isPaired,
                onOpenDrawer: onOpenDrawer,
                onNewChat: newChat
            )

            if session.isPaired {
                conversationBody
            } else {
                unpairedBody
            }
        }
        .background(.background)
        .task(id: transcriptKey) { await loadTranscript() }
        .sensoryFeedback(.impact(weight: .light), trigger: sendFeedback)
        .sensoryFeedback(.error, trigger: errorFeedback)
    }

    // MARK: - States

    @ViewBuilder
    private var conversationBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if messages.isEmpty, isLoadingTranscript {
                    LoadingState("Loading conversation…")
                        .padding(.top, 80)
                } else if messages.isEmpty, case .load(let message)? = failure {
                    transcriptErrorState(message)
                        .padding(.top, 60)
                } else if messages.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if isLoadingTranscript {
                            LoadingRow("Loading conversation…")
                                .padding(.horizontal)
                        }
                        ForEach(messages) { message in
                            ChatBubbleRow(message: message).id(message.id)
                        }
                        // A refresh that fails while the thread is still
                        // on screen — inline so the existing turns stay.
                        if case .load(let message)? = failure {
                            ErrorBanner(message: message) { await loadTranscript(force: true) }
                                .transition(.opacity)
                        }
                        if isSending {
                            ThinkingIndicator()
                        }
                    }
                    .padding(.vertical, 18)
                }
            }
            .refreshable { await loadTranscript(force: true) }
            .onChange(of: messages.count) {
                if let last = messages.last {
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }

        // A failed send shows a banner with Retry directly above the
        // composer; a failed transcript load takes over the body above.
        if case .send(let message)? = failure {
            ErrorBanner(message: message) { await retrySend() }
                .padding(.bottom, 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }

        ChatComposer(
            draft: $draft,
            inputFocused: $inputFocused,
            isSending: isSending,
            disabled: isLoadingTranscript,
            onSend: send
        )
    }

    /// Full-bleed transcript-load failure with a Retry CTA — shown when
    /// the conversation couldn't be fetched at all.
    private func transcriptErrorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't load conversation", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                Task { await loadTranscript(force: true) }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var unpairedBody: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "link.badge.plus")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Pair this iPhone with swooshd")
                .font(.title3.weight(.semibold))
            Text("Open the drawer → Settings and paste the bearer token from your Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Text(greeting)
                    .font(.system(size: 28, weight: .semibold))
                Text("How can I help you today?")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 24)

            VStack(spacing: 10) {
                ForEach(suggestedPrompts, id: \.self) { prompt in
                    Button {
                        draft = prompt
                        inputFocused = true
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.tint)
                            Text(prompt)
                                .multilineTextAlignment(.leading)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Hello"
        }
    }

    // MARK: - Transcript

    private var transcriptKey: String? {
        session.host.map { "\($0.absoluteString)#\(session.sessionID)" }
    }

    /// Load the transcript. `force` bypasses the already-loaded guard so
    /// pull-to-refresh and the Retry button always re-fetch.
    private func loadTranscript(force: Bool = false) async {
        guard session.isPaired, let client = session.client(), let transcriptKey else {
            messages = []
            loadedTranscriptKey = nil
            return
        }
        guard force || loadedTranscriptKey != transcriptKey else { return }
        withAnimation(.easeOut(duration: 0.22)) {
            isLoadingTranscript = true
            failure = nil
        }
        defer { withAnimation(.easeOut(duration: 0.22)) { isLoadingTranscript = false } }
        do {
            let transcript = try await client.transcript(sessionID: session.sessionID)
            withAnimation(.easeOut(duration: 0.22)) {
                messages = transcript.messages.compactMap(ChatBubble.init)
            }
            loadedTranscriptKey = transcriptKey
        } catch {
            failure = .load(error.localizedDescription)
            errorFeedback &+= 1
        }
    }

    // MARK: - Send

    private func send() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending, !isLoadingTranscript else { return }
        draft = ""
        Task { await deliver(trimmed) }
    }

    /// Re-run the last failed send without making the user retype.
    private func retrySend() async {
        guard let text = lastSentText, !isSending else { return }
        await deliver(text, isRetry: true)
    }

    /// Append the user turn (unless retrying — the bubble is already
    /// there) and round-trip to the daemon.
    private func deliver(_ text: String, isRetry: Bool = false) async {
        guard let executor = session.executor() else {
            failure = .send("Not paired with a daemon.")
            errorFeedback &+= 1
            return
        }
        lastSentText = text
        if !isRetry {
            withAnimation(.easeOut(duration: 0.22)) {
                messages.append(ChatBubble(role: .user, text: text))
            }
            sendFeedback &+= 1   // haptic: message sent
        }
        withAnimation(.easeOut(duration: 0.22)) {
            isSending = true
            failure = nil
        }
        defer { withAnimation(.easeOut(duration: 0.22)) { isSending = false } }
        do {
            let response = try await executor.run(
                ChatRequest(sessionID: session.sessionID, input: text)
            )
            withAnimation(.easeOut(duration: 0.22)) {
                messages.append(ChatBubble(role: .agent, text: response.message))
            }
            lastSentText = nil
        } catch {
            withAnimation(.easeOut(duration: 0.22)) {
                failure = .send(error.localizedDescription)
            }
            errorFeedback &+= 1   // haptic: send failed
        }
    }

    private func newChat() {
        withAnimation(.easeOut(duration: 0.22)) {
            messages = []
            failure = nil
        }
        loadedTranscriptKey = nil
        lastSentText = nil
        draft = ""
        inputFocused = true
    }
}

// MARK: - Top bar

private struct ChatTopBar: View {
    let model: String?
    let paired: Bool
    let onOpenDrawer: () -> Void
    let onNewChat: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onOpenDrawer) {
                Image(systemName: "line.3.horizontal")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Open drawer")

            Spacer()

            VStack(spacing: 0) {
                Text("Detour").font(.body.weight(.semibold))
                if let model {
                    Text(model)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if !paired {
                    Text("Not paired").font(.caption2).foregroundStyle(.red)
                }
            }

            Spacer()

            Button(action: onNewChat) {
                Image(systemName: "square.and.pencil")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("New chat")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.regularMaterial)
        .overlay(Divider(), alignment: .bottom)
    }
}

// MARK: - Bubble + composer

private struct ChatBubbleRow: View {
    let message: ChatBubble

    var body: some View {
        HStack(alignment: .top) {
            switch message.role {
            case .user:
                Spacer(minLength: 56)
                Text(message.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .foregroundStyle(.primary)
            case .agent:
                Text(message.text)
                    .padding(.horizontal, 4)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
    }
}

private struct ThinkingIndicator: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Thinking…").foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 4)
    }
}

private struct ChatComposer: View {
    @Binding var draft: String
    var inputFocused: FocusState<Bool>.Binding
    let isSending: Bool
    let disabled: Bool
    let onSend: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            HStack(alignment: .bottom, spacing: 0) {
                TextField("Message Swoosh", text: $draft, axis: .vertical)
                    .lineLimit(1...6)
                    .focused(inputFocused)
                    .submitLabel(.send)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )

            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(sendDisabled ? Color.gray.opacity(0.35) : Color.accentColor)
                    )
            }
            .disabled(sendDisabled)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    private var sendDisabled: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending || disabled
    }
}

// MARK: - Bubble model

struct ChatBubble: Identifiable, Equatable, Sendable {
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
