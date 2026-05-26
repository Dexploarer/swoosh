// DetourCanvasArtifactPanel.swift — canvas inspector and artifact preview (0.5A)

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct DetourCanvasArtifactPanel: View {
    let workspace: DetourCanvasWorkspace
    let selectedNode: DetourCanvasNode?
    @Binding var selectedArtifactID: String?
    let reviewSetup: () -> Void
    @State private var isEditingArtifact = false
    @State private var draftArtifactID: String?
    @State private var draftMarkdown = ""

    private var artifact: DetourCanvasArtifact? {
        if let selectedArtifactID,
           let match = workspace.artifacts.first(where: { $0.id == selectedArtifactID }) {
            return match
        }
        return workspace.artifacts.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            nodeInspector
            artifactPicker
            if let artifact {
                artifactPreview(artifact)
            }
            Spacer(minLength: 0)
            Button {
                reviewSetup()
            } label: {
                Label("Setup", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(18)
        .frame(width: 380)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial)
        .onAppear {
            selectedArtifactID = artifact?.id
        }
    }

    private var nodeInspector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Inspector")
                .font(.title3.weight(.semibold))
            if let selectedNode {
                HStack(spacing: 10) {
                    Image(systemName: selectedNode.systemImage)
                        .foregroundStyle(selectedNode.tone.color)
                        .frame(width: 30, height: 30)
                        .background(selectedNode.tone.color.opacity(0.14), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedNode.title)
                            .font(.headline)
                        Text(selectedNode.status.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selectedNode.tone.color)
                    }
                }
                Text(selectedNode.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Select a node to inspect its role.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .detourLiquidGlass(cornerRadius: 18)
    }

    private var artifactPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(workspace.artifacts) { artifact in
                    Button {
                        selectedArtifactID = artifact.id
                    } label: {
                        Label(artifact.title, systemImage: artifact.kind.systemImage)
                            .labelStyle(.titleAndIcon)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                artifact.id == selectedArtifactID ? Color.accentColor.opacity(0.22) : Color.white.opacity(0.07),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func artifactPreview(_ artifact: DetourCanvasArtifact) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(artifact.title)
                            .font(.headline)
                        Text(artifact.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(artifact.status.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor(artifact.status))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor(artifact.status).opacity(0.12), in: Capsule())
                    Button {
                        copy(isEditingArtifact ? draftMarkdown : artifact.markdown)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    Button {
                        prepareDraft(artifact)
                        isEditingArtifact.toggle()
                    } label: {
                        Image(systemName: isEditingArtifact ? "eye" : "pencil")
                    }
                    .buttonStyle(.borderless)
                }
                if isEditingArtifact {
                    TextEditor(text: $draftMarkdown)
                        .font(.system(.callout, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 260)
                        .padding(10)
                        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .textSelection(.enabled)
                } else {
                    DetourStreamdownRenderer(markdown: artifact.markdown)
                }
            }
            .padding(14)
        }
        .detourLiquidGlass(cornerRadius: 18)
        .onAppear {
            prepareDraft(artifact)
        }
        .onChange(of: artifact.id) { _, _ in
            prepareDraft(artifact)
        }
    }

    private func statusColor(_ status: DetourCanvasStatus) -> Color {
        switch status {
        case .ready, .live: .green
        case .pending: .blue
        case .needsSetup, .offline: .orange
        }
    }

    private func prepareDraft(_ artifact: DetourCanvasArtifact) {
        guard draftArtifactID != artifact.id else { return }
        draftArtifactID = artifact.id
        draftMarkdown = artifact.markdown
        isEditingArtifact = false
    }

    private func copy(_ value: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
    }
}
