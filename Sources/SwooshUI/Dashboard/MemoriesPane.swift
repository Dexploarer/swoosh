// SwooshUI/Dashboard/MemoriesPane.swift — Live memories view — 0.9V
//
// Fetches from /api/memories and shows approved, pending, and rejected
// memory categories with confidence indicators and review actions.

import SwiftUI
import SwooshGenerativeUI
import SwooshClient

public struct MemoriesPane: View {
    @State private var approved: [MemorySummary] = []
    @State private var pending: [MemorySummary] = []
    @State private var rejected: [MemorySummary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedTab = 0

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            tabBar
            Divider().background(SwooshNeonTokens.Line.rule)
            if isLoading && approved.isEmpty && pending.isEmpty {
                loadingView
            } else {
                memoryList
            }
        }
        .background(SwooshNeonTokens.Canvas.bg)
        .task { await loadMemories() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Memories")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                Text("\(approved.count) approved · \(pending.count) pending")
                    .font(.system(size: 12))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            }
            Spacer()
            Button {
                Task { await loadMemories() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text2)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 2) {
            memoryTab("Approved", count: approved.count, index: 0, color: VoltPaper.accent)
            memoryTab("Pending", count: pending.count, index: 1, color: VoltPaper.Chart.c4)
            memoryTab("Rejected", count: rejected.count, index: 2, color: VoltPaper.destructive)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    private func memoryTab(_ label: String, count: Int, index: Int, color: Color) -> some View {
        let isSelected = selectedTab == index
        return Button {
            selectedTab = index
        } label: {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(label)
                Text("(\(count))")
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            }
            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? SwooshNeonTokens.Canvas.text1 : SwooshNeonTokens.Canvas.text2)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? VoltPaper.foreground.opacity(0.06) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Memory list

    private var currentList: [MemorySummary] {
        switch selectedTab {
        case 0: return approved
        case 1: return pending
        case 2: return rejected
        default: return approved
        }
    }

    private var memoryList: some View {
        ScrollView {
            if currentList.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 4) {
                    ForEach(currentList) { memory in
                        memoryRow(memory)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
        }
    }

    private func memoryRow(_ memory: MemorySummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(memory.text)
                    .font(.system(size: 13))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                    .lineLimit(3)
                Spacer()
                sensitivityBadge(memory.sensitivity)
            }
            HStack(spacing: 12) {
                categoryBadge(memory.category)
                if let conf = memory.confidence {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar")
                            .font(.system(size: 9))
                        Text("\(Int(conf * 100))%")
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                }
                Spacer()
                Text(memory.createdAt)
                    .font(.system(size: 10))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            }
        }
        .padding(12)
        .background(VoltPaper.foreground.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(SwooshNeonTokens.Line.rule, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func categoryBadge(_ category: String) -> some View {
        let color = categoryColor(category)
        Text(category)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func sensitivityBadge(_ sensitivity: String) -> some View {
        let color: Color = sensitivity == "high" ? VoltPaper.destructive :
                           sensitivity == "medium" ? VoltPaper.Chart.c4 : VoltPaper.mutedFg
        Text(sensitivity.uppercased())
            .font(.system(size: 8, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
    }

    private func categoryColor(_ category: String) -> Color {
        switch category.lowercased() {
        case "preference": return VoltPaper.Chart.c1
        case "fact": return SwooshNeonTokens.Accent.cyan
        case "context": return VoltPaper.Chart.c5
        case "personality": return VoltPaper.Chart.c4
        case "routine": return VoltPaper.Chart.c2
        default: return VoltPaper.mutedFg
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text("Loading memories…")
                .font(.system(size: 12))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 32, weight: .ultraLight))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3.opacity(0.4))
            Text("No memories in this category")
                .font(.system(size: 14))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Network

    private func loadMemories() async {
        guard let client = SwooshDaemonClient.client() else {
            errorMessage = "Daemon not reachable."
            isLoading = false
            return
        }
        isLoading = true
        do {
            let response = try await client.memories()
            approved = response.approved
            pending = response.pending
            rejected = response.rejected
            errorMessage = nil
        } catch {
            errorMessage = "Failed: \(error.localizedDescription)"
        }
        isLoading = false
    }
}


