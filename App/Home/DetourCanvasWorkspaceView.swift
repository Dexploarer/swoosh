// DetourCanvasWorkspaceView.swift — expandable generated node canvas (0.5A)

import SwiftUI

struct DetourCanvasWorkspaceView: View {
    @ObservedObject var store: OnboardingStore
    let sections: [DetourSetupInsightSection]
    let summary: DetourSetupCapabilitySummary
    @ObservedObject var wallet: DetourHomeWalletModel
    @ObservedObject var inbox: DetourHomeInboxModel
    @Binding var kind: DetourCanvasKind
    @Binding var request: String
    let reviewSetup: () -> Void
    let close: () -> Void
    @State private var selectedNodeID: String?
    @State private var selectedArtifactID: String?

    var body: some View {
        let workspace = DetourCanvasWorkspaceBuilder.build(
            kind: kind,
            request: request,
            sections: sections,
            summary: summary,
            wallet: wallet,
            inbox: inbox
        )
        VStack(spacing: 0) {
            topBar(workspace)
            HStack(spacing: 0) {
                canvas(workspace)
                Divider()
                DetourCanvasArtifactPanel(
                    workspace: workspace,
                    selectedNode: selectedNode(workspace),
                    selectedArtifactID: $selectedArtifactID,
                    reviewSetup: reviewSetup
                )
            }
        }
        .background(.clear)
        .onChange(of: kind) { _, _ in
            selectedNodeID = nil
            selectedArtifactID = nil
        }
    }

    private func topBar(_ workspace: DetourCanvasWorkspace) -> some View {
        HStack(spacing: 14) {
            Button {
                close()
            } label: {
                Label("Command center", systemImage: "sidebar.left")
            }
            .buttonStyle(.bordered)
            TextField("Tell Detour what canvas to open", text: $request)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    kind = DetourCanvasKind.infer(from: request)
                }
            Picker("Canvas", selection: $kind) {
                ForEach(DetourCanvasKind.allCases) { canvasKind in
                    Text(canvasKind.title).tag(canvasKind)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 430)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .accessibilityLabel("\(workspace.title). \(workspace.subtitle)")
    }

    private func canvas(_ workspace: DetourCanvasWorkspace) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            header(workspace)
            GeometryReader { proxy in
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                    connectionLayer(workspace)
                    LazyVGrid(columns: canvasColumns(width: proxy.size.width), spacing: 16) {
                        ForEach(workspace.nodes) { node in
                            Button {
                                selectedNodeID = node.id
                            } label: {
                                DetourCanvasNodeCard(node: node, isSelected: selectedNodeID == node.id)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(22)
                }
            }
        }
        .padding(22)
    }

    private func header(_ workspace: DetourCanvasWorkspace) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(workspace.title)
                    .font(.title.weight(.semibold))
                Text(workspace.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !workspace.request.isEmpty {
                Text(workspace.request)
                    .font(.callout)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
            }
        }
    }

    private func canvasColumns(width: CGFloat) -> [GridItem] {
        let minimum = width > 980 ? 230.0 : 200.0
        return [GridItem(.adaptive(minimum: minimum), spacing: 16)]
    }

    private func selectedNode(_ workspace: DetourCanvasWorkspace) -> DetourCanvasNode? {
        if let selectedNodeID,
           let match = workspace.nodes.first(where: { $0.id == selectedNodeID }) {
            return match
        }
        return workspace.nodes.first
    }

    private func connectionLayer(_ workspace: DetourCanvasWorkspace) -> some View {
        Canvas { context, canvasSize in
            guard workspace.edges.count > 0 else { return }
            let y = canvasSize.height / 2
            var path = Path()
            path.move(to: CGPoint(x: canvasSize.width * 0.18, y: y))
            path.addLine(to: CGPoint(x: canvasSize.width * 0.82, y: y))
            context.stroke(path, with: .color(.accentColor.opacity(0.22)), lineWidth: 2)
        }
        .allowsHitTesting(false)
        .padding(.vertical, 70)
    }
}

private struct DetourCanvasNodeCard: View {
    let node: DetourCanvasNode
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Image(systemName: node.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(node.tone.color)
                    .frame(width: 32, height: 32)
                    .background(node.tone.color.opacity(0.14), in: Circle())
                Spacer()
                Text(node.status.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(node.tone.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(node.tone.color.opacity(0.12), in: Capsule())
            }
            Text(node.title)
                .font(.headline)
            Text(node.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(node.tone.color.opacity(isSelected ? 0.72 : 0.16), lineWidth: isSelected ? 2 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}
