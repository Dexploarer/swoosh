// Apps/SwooshiOS/AgentRoot.swift — iOS chat surface backed by AgentShellView
//
// Replaces the standalone ChatScreen. Reuses the cross-platform
// AgentShellModel + AgentShellView, plumbs the iOS pairing client into
// `shell.send`, and renders a compact voice pill as a bottom sheet
// (iOS doesn't have floating windows the way macOS does).
//
// Composer attachments: the `+` button in AgentShellView opens an
// AttachmentSheet that calls back into the host. Files / Photos /
// Camera are wired here because the system pickers are iOS-only and
// SwooshUI is cross-platform. Each picker, on success, appends an
// `[Attached … name]` token to the chat input so the user gets a
// visible record of what they attached. A real upload endpoint on
// the daemon side will replace the token wiring later.

import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers
import SwooshClient
import SwooshGenerativeUI
import SwooshUI
import SwooshVoiceProviders
#if os(iOS)
import SwooshLocalLLM
import SwooshLocalVoice
#endif

struct AgentRoot: View {
    @Environment(ClientSession.self) private var session
    let shell: AgentShellModel
    @State private var tts = TTSEngine()
    @State private var voice: VoiceMode? = nil
    @State private var wiredExecutor = false
    @State private var showVoicePill = false
    @State private var levelSource = AudioLevelSource()

    // Attachment pickers
    @State private var showingFileImporter = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showingPhotoPicker = false
    @State private var showingCamera = false

    let onOpenDrawer: () -> Void
    /// Push a drawer destination onto RootView's NavigationStack. Used by
    /// the composer's `+` attachment menu so tapping Skills / MCP / etc.
    /// actually goes somewhere.
    let onNavigate: (DrawerDestination) -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            shellSurface
            LiquidVoiceSphere(onTap: { toggleVoicePill() })
                .environment(levelSource)
            if showVoicePill, let voice {
                IOSVoicePill(voice: voice, onClose: { closePill() })
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .environment(shell)
        .background(SwooshNeonTokens.Canvas.bg.ignoresSafeArea())
        .task { wireExecutor() }
        .task {
            // Stand up audio metering + haptics for the liquid sphere.
            levelSource.bind(shell: shell, playback: VoiceRouter.shared.playback)
            VoiceHapticsCoordinator.shared.start()
        }
        .onDisappear {
            levelSource.detach()
            VoiceHapticsCoordinator.shared.stop()
        }
        .onChange(of: session.isPaired) { _, _ in
            wiredExecutor = false
            wireExecutor()
        }
        .toolbar { toolbarContent }
        .animation(.spring(duration: 0.3), value: showVoicePill)
        // Attachment pickers — declared once at the AgentRoot level so the
        // bindings stay stable across body re-renders.
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .photosPicker(
            isPresented: $showingPhotoPicker,
            selection: $photoPickerItem,
            matching: .images
        )
        .onChange(of: photoPickerItem) { _, newItem in
            handlePhotoPick(newItem)
        }
        .sheet(isPresented: $showingCamera) {
            CameraCaptureSheet { image in
                handleCameraCapture(image)
                showingCamera = false
            } onCancel: {
                showingCamera = false
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Shell

    private var shellSurface: some View {
        AgentShellView(
            shell: shell,
            mode: .phone,
            attachmentActions: AttachmentActions(
                attachFile:   { showingFileImporter = true },
                attachPhoto:  { showingPhotoPicker = true },
                attachCamera: { showingCamera = true },
                openSkills:   { onNavigate(.connections) },
                openMCP:      { onNavigate(.mcpServers) }
            )
        )
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: onOpenDrawer) {
                Image(systemName: "line.3.horizontal")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                voice?.toggle()
                showVoicePill = voice?.isActive ?? false
            } label: {
                Image(systemName: showVoicePill ? "waveform.circle.fill" : "mic.fill")
                    .foregroundStyle(SwooshNeonTokens.Accent.cyan)
            }
        }
    }

    // MARK: - Attachment handlers

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let name = url.lastPathComponent
            appendAttachment("file", name: name)
        case .failure(let error):
            shell.messages.append(.init(
                role: .agent,
                text: "Couldn't open that file: \(error.localizedDescription)"
            ))
        }
    }

    private func handlePhotoPick(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task { @MainActor in
            // Pull image data to confirm the asset is loadable; surface
            // failures clearly. The image bytes themselves stay on-device
            // until a real upload endpoint exists daemon-side.
            do {
                if let data = try await item.loadTransferable(type: Data.self) {
                    let kb = max(1, data.count / 1024)
                    appendAttachment("photo", name: "image (\(kb) KB)")
                } else {
                    appendAttachment("photo", name: "image")
                }
            } catch {
                shell.messages.append(.init(
                    role: .agent,
                    text: "Couldn't read the photo: \(error.localizedDescription)"
                ))
            }
            photoPickerItem = nil
        }
    }

    private func handleCameraCapture(_ image: UIImage?) {
        guard let image else { return }
        let bytes = image.jpegData(compressionQuality: 0.85)?.count ?? 0
        let kb = max(1, bytes / 1024)
        appendAttachment("camera", name: "snapshot (\(kb) KB)")
    }

    /// Append a tagged attachment marker to the chat input so the user
    /// sees what they attached. Real upload routing lands when the daemon
    /// exposes `/api/agent/attachments`.
    private func appendAttachment(_ kind: String, name: String) {
        let token = "[\(kind): \(name)] "
        shell.input = token + shell.input
    }

    // MARK: - Wiring

    private func wireExecutor() {
        guard !wiredExecutor else { return }
        wiredExecutor = true
        if voice == nil {
            voice = VoiceMode(shell: shell, tts: tts)
        }
        guard let executor = session.executor() else {
            // Not paired — overwrite the SwooshUI default-echo placeholder
            // with a Detour-voiced explanation so the user sees a real
            // diagnostic instead of "Detour (placeholder): hi".
            shell.send = { @MainActor _, shellModel in
                try? await Task.sleep(nanoseconds: 200_000_000)
                shellModel.messages.append(.init(
                    role: .agent,
                    text: "I'm not connected to your Mac yet. Open the side drawer → Settings → Pair with swooshd, paste the bearer token, then come back here to chat."
                ))
            }
            return
        }
        // Wrap shell.send: persist + route to executor + speak through
        // the user's currently-chosen cloud TTS (if configured). The
        // system fallback uses the existing AVSpeechSynthesizer path
        // via VoiceMode.speakReplies/TTSEngine.
        let baseHandler = AgentShellBackends.swooshExecutor(
            executor,
            sessionID: session.sessionID,
            localModelClassifier: { modelID in
                LiteRTModelCatalog.all
                    .first(where: { $0.id == modelID })?
                    .displayName
            }
        )
        shell.send = { @MainActor text, shellModel in
            await baseHandler(text, shellModel)
            guard let lastReply = shellModel.messages.last,
                  lastReply.role == .agent,
                  VoiceRouter.shared.isCurrentTTSConfigured(),
                  VoiceRouter.shared.currentTTSChoice != .system
            else { return }
            // On-device path: local provider returns a complete WAV;
            // play through VoiceRouter.playback.
            if let localProvider = LocalTTSResolver.provider(for: VoiceRouter.shared.currentTTSChoice) {
                let cloneID = ActiveClonePreference.current
                // A clone selection only applies to PocketTTS (the only
                // engine wired to LocalVoiceCloneStore). Surface the
                // mismatch when the user switches engines so we don't
                // silently route Kokoro/StyleTTS2/etc. through the
                // (irrelevant) cached clone id.
                if cloneID != nil, VoiceRouter.shared.currentTTSChoice != .pocketTTSLocal {
                    ActiveClonePreference.current = nil
                }
                do {
                    let result: TTSResult
                    if let cloneID, VoiceRouter.shared.currentTTSChoice == .pocketTTSLocal {
                        result = try await localProvider.synthesize(text: lastReply.text, cloneID: cloneID)
                    } else {
                        result = try await localProvider.synthesize(text: lastReply.text, voiceID: nil, format: .wav)
                    }
                    try VoiceRouter.shared.playback.play(result)
                } catch {
                    // Local TTS failed — fall through silently; user still has text + system fallback.
                }
                return
            }
            // Cloud path: streamed via existing chunked player.
            guard let provider = try? VoiceRouter.shared.activeCloudTTSProvider() else { return }
            do {
                let stream = provider.synthesizeStream(
                    text: lastReply.text,
                    voiceID: nil,
                    format: .mp3
                )
                await VoiceRouter.shared.streamingPlayer.play(stream: stream, format: .mp3)
            } catch {
                // Fall back silently.
            }
        }
    }

    /// Sphere-tap action: toggle the voice pill and the underlying mic.
    /// Mirrors the toolbar mic-button behaviour so the floating sphere
    /// becomes the natural one-handed control.
    private func toggleVoicePill() {
        voice?.toggle()
        showVoicePill = voice?.isActive ?? false
    }

    private func closePill() {
        voice?.stop()
        showVoicePill = false
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Camera capture
// ═══════════════════════════════════════════════════════════════════

/// Thin UIViewControllerRepresentable around UIImagePickerController for
/// camera capture. SwiftUI doesn't have a first-party camera view as of
/// iOS 26, so this is the canonical way to invoke the system camera.
private struct CameraCaptureSheet: UIViewControllerRepresentable {
    let onCapture: (UIImage?) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage?) -> Void
        let onCancel: () -> Void

        init(onCapture: @escaping (UIImage?) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onCapture(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}
