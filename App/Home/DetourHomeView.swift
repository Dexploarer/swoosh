// DetourHomeView.swift — primary Detour desktop workspace (0.5A)

import SwiftUI

struct DetourHomeView: View {
    @ObservedObject var store: OnboardingStore
    @State private var focus = DetourHomeFocus.overview
    @State private var command = ""
    @State private var runningScan = false
    @State private var applyingSetup = false
    @State private var workspaceMode = DetourHomeWorkspaceMode.commandCenter
    @State private var canvasKind = DetourCanvasKind.workflow
    @State private var canvasRequest = ""
    @State private var chatIntegrationSurface: DetourChatIntegrationSurface?
    @StateObject private var daemon = DetourDaemonSupervisor.shared
    @StateObject private var wallet = DetourHomeWalletModel()
    @StateObject private var inbox = DetourHomeInboxModel()

    var body: some View {
        let snapshot = store.setupInsightSnapshot
        let sections = visibleSections(snapshot.sections)
        ZStack {
            DetourHomeSurface()
            if workspaceMode == .canvas {
                DetourCanvasWorkspaceView(
                    store: store,
                    sections: sections,
                    summary: snapshot.summary,
                    wallet: wallet,
                    inbox: inbox,
                    kind: $canvasKind,
                    request: $canvasRequest,
                    reviewSetup: reviewSetup,
                    close: closeCanvas
                )
                .transition(.opacity)
            } else {
                DetourHomeDashboard(
                    store: store,
                    sections: sections,
                    summary: snapshot.summary,
                    focus: $focus,
                    command: $command,
                    wallet: wallet,
                    inbox: inbox,
                    runningScan: runningScan,
                    applyingSetup: applyingSetup,
                    chatIntegrationSurface: chatIntegrationSurface,
                    submitCommand: submitCommand,
                    reviewSetup: reviewSetup,
                    applySetup: applySetup,
                    runScan: runScan,
                    openCanvas: { openCanvas(request: command) },
                    action: handleAction
                )
                .transition(.opacity)
            }
        }
        .frame(minWidth: 980, minHeight: 660)
        .preferredColorScheme(.dark)
        .onAppear(perform: refreshRuntimeState)
    }

    private func refreshRuntimeState() {
        Task { @MainActor in
            do {
                try await daemon.ensureRunning()
            } catch {
                let message = DetourHomeDaemonClient.display(error)
                wallet.markOffline(message)
                inbox.markOffline(message)
                return
            }
            if wallet.state == .idle { wallet.refresh() }
            if inbox.state == .idle { inbox.refresh() }
        }
    }

    private func visibleSections(_ sections: [DetourSetupInsightSection]) -> [DetourSetupInsightSection] {
        sections.map { section in
            DetourSetupInsightSection(
                id: section.id,
                title: section.title,
                subtitle: section.subtitle,
                detail: section.detail,
                items: section.items.filter { $0.status != .removed }
            )
        }
        .filter { !$0.items.isEmpty }
    }

    private func submitCommand() {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if shouldOpenCanvas(trimmed) {
            openCanvas(request: trimmed)
        } else if DetourChatIntegrationSurfaceBuilder.isIntegrationRequest(trimmed),
                  let surface = DetourChatIntegrationSurfaceBuilder.build(store: store, request: trimmed) {
            chatIntegrationSurface = surface
            focus = .overview
        } else {
            focus = DetourHomeFocus.infer(from: trimmed)
        }
    }

    private func shouldOpenCanvas(_ text: String) -> Bool {
        let command = text.lowercased()
        let canvasWords = ["canvas", "nodes", "node", "workflow", "comfy", "rag", "knowledge graph", "prompt graph"]
        return canvasWords.contains { command.contains($0) }
    }

    private func handleAction(_ action: DetourSetupInsightAction) {
        switch action.kind {
        case .use:
            store.setSetupInsightCandidateApproval(publicID: action.targetID, approved: true)
        case .remove:
            store.removeSetupInsightCandidateFromContext(publicID: action.targetID)
        case .scopeUser:
            store.setSetupInsightCandidateScope(publicID: action.targetID, role: .user)
        case .scopeAgent:
            store.setSetupInsightCandidateScope(publicID: action.targetID, role: .agent)
        case .grantPermission, .configure, .openDoctor, .openRelationshipQA:
            focus = .settings
        }
    }

    private func openCanvas(request: String) {
        let trimmed = request.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            canvasRequest = trimmed
            canvasKind = DetourCanvasKind.infer(from: trimmed)
        }
        workspaceMode = .canvas
        DetourWindowActions.expandForCanvas()
    }

    private func closeCanvas() {
        workspaceMode = .commandCenter
        DetourWindowActions.fitHomeWindow()
    }

    private func reviewSetup() {
        focus = .setup
        workspaceMode = .commandCenter
        DetourWindowActions.fitHomeWindow()
        DetourWindowActions.showMainWindow()
    }

    private func runScan() {
        guard !runningScan else { return }
        runningScan = true
        store.startInAppConfigurationScan()
        Task { @MainActor in
            await store.runInAppConfigurationScan { _ in }
            wallet.refresh()
            inbox.refresh()
            runningScan = false
            focus = .setup
        }
    }

    private func applySetup() {
        guard !applyingSetup else { return }
        applyingSetup = true
        Task { @MainActor in
            _ = await store.applySetupFromPersonalizationReview { _ in }
            wallet.refresh()
            inbox.refresh()
            applyingSetup = false
        }
    }
}
