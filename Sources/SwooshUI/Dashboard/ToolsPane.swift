// SwooshUI/Dashboard/ToolsPane.swift — Live tool catalog — 0.9V
//
// Fetches from /api/tools, groups by toolset, shows risk badges and
// permission requirements for each tool.

import SwiftUI
import SwooshGenerativeUI
import SwooshClient

public struct ToolsPane: View {
    @State private var tools: [ToolCatalogToolSummary] = []
    @State private var toolsets: [ToolsetSummary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var selectedToolset: String?

    public init() {}

    private var filteredTools: [ToolCatalogToolSummary] {
        var result = tools
        if let ts = selectedToolset {
            result = result.filter { $0.toolset == ts }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.displayName.lowercased().contains(q) ||
                $0.description.lowercased().contains(q) ||
                $0.name.lowercased().contains(q)
            }
        }
        return result
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            toolsetBar
            Divider().background(SwooshNeonTokens.Line.rule)
            if isLoading && tools.isEmpty {
                loadingView
            } else if let errorMessage {
                errorView(errorMessage)
            } else {
                toolList
            }
        }
        .background(SwooshNeonTokens.Canvas.bg)
        .task { await loadTools() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tools")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                    Text("\(tools.count) registered across \(toolsets.count) toolsets")
                        .font(.system(size: 12))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                }
                Spacer()
                Button {
                    Task { await loadTools() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                TextField("Search tools…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
            }
            .padding(8)
            .background(VoltPaper.foreground.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(SwooshNeonTokens.Line.rule, lineWidth: 0.5)
            )
        }
        .padding(24)
        .padding(.bottom, 0)
    }

    // MARK: - Toolset bar

    private var toolsetBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                toolsetChip("All", id: nil)
                ForEach(toolsets) { ts in
                    toolsetChip(ts.id, id: ts.id, count: ts.toolCount)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
    }

    private func toolsetChip(_ label: String, id: String?, count: Int? = nil) -> some View {
        let selected = selectedToolset == id
        return Button {
            selectedToolset = id
        } label: {
            HStack(spacing: 4) {
                Text(label)
                if let count {
                    Text("(\(count))")
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                }
            }
            .font(.system(size: 11, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? SwooshNeonTokens.Accent.cyan : SwooshNeonTokens.Canvas.text2)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(selected ? SwooshNeonTokens.Accent.cyan.opacity(0.12) : Color.white.opacity(0.03))
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(
                    selected ? SwooshNeonTokens.Accent.cyan.opacity(0.3) : SwooshNeonTokens.Line.rule,
                    lineWidth: 0.5
                )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tool list

    private var toolList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(filteredTools) { tool in
                    toolRow(tool)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }

    private func toolRow(_ tool: ToolCatalogToolSummary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: toolIcon(for: tool.toolset))
                .font(.system(size: 14))
                .foregroundStyle(riskColor(tool.risk))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(tool.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                    riskBadge(tool.risk)
                    if tool.approval == "humanOnly" {
                        Text("HUMAN")
                            .font(.system(size: 8, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(VoltPaper.Chart.c4)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(VoltPaper.Chart.c4.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                Text(tool.description)
                    .font(.system(size: 11))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                    .lineLimit(1)
            }
            Spacer()
            Text(tool.permission)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(VoltPaper.foreground.opacity(0.015))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func riskBadge(_ risk: String) -> some View {
        let color = riskColor(risk)
        Text(risk.uppercased())
            .font(.system(size: 8, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func riskColor(_ risk: String) -> Color {
        switch risk.lowercased() {
        case "high", "critical": return VoltPaper.destructive
        case "medium": return VoltPaper.Chart.c4
        case "low": return VoltPaper.accent
        default: return VoltPaper.mutedFg
        }
    }

    private func toolIcon(for toolset: String) -> String {
        switch toolset.lowercased() {
        case "core": return "cube"
        case "memory", "memories": return "brain.head.profile"
        case "scout": return "binoculars"
        case "files", "file": return "folder"
        case "git": return "arrow.triangle.branch"
        case "swiftdev", "swift": return "swift"
        case "evm": return "diamond"
        case "solana": return "circle.hexagonpath"
        case "hyperliquid": return "chart.line.uptrend.xyaxis"
        case "uniswap", "jupiter": return "arrow.left.arrow.right"
        case "mcp": return "puzzlepiece.extension"
        case "terminal": return "terminal"
        case "workflow": return "flowchart"
        case "permissions": return "lock.shield"
        case "gaming": return "gamecontroller"
        case "media", "mediagen": return "photo.artframe"
        default: return "wrench"
        }
    }

    // MARK: - Loading & Error

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text("Loading tool catalog…")
                .font(.system(size: 12))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(VoltPaper.Chart.c4.opacity(0.5))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Network

    private func loadTools() async {
        guard let client = SwooshDaemonClient.client() else {
            errorMessage = "Daemon not reachable."
            isLoading = false
            return
        }
        isLoading = true
        do {
            let response = try await client.toolCatalog()
            tools = response.tools
            toolsets = response.toolsets
            errorMessage = nil
        } catch {
            errorMessage = "Failed: \(error.localizedDescription)"
        }
        isLoading = false
    }
}


