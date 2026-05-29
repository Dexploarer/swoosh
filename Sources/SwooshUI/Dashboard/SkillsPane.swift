// SwooshUI/Dashboard/SkillsPane.swift — Live skills catalog — 0.9V
//
// Fetches from /api/skills and shows bundled + user-authored skills with
// trust level badges, category grouping, and search.

import SwiftUI
import SwooshGenerativeUI
import SwooshClient

public struct SkillsPane: View {
    @State private var skills: [SkillSummary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var selectedCategory: String?

    public init() {}

    private var categories: [String] {
        Array(Set(skills.map(\.category))).sorted()
    }

    private var filteredSkills: [SkillSummary] {
        var result = skills
        if let cat = selectedCategory {
            result = result.filter { $0.category == cat }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(q) ||
                $0.description.lowercased().contains(q)
            }
        }
        return result
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            categoryBar
            Divider().background(SwooshNeonTokens.Line.rule)
            if isLoading && skills.isEmpty {
                loadingView
            } else {
                skillGrid
            }
        }
        .background(SwooshNeonTokens.Canvas.bg)
        .task { await loadSkills() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Skills")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                    Text("\(skills.count) skills loaded")
                        .font(.system(size: 12))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                }
                Spacer()
                Button {
                    Task { await loadSkills() }
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
                TextField("Search skills…", text: $searchText)
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
    }

    // MARK: - Category bar

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                catChip("All", id: nil)
                ForEach(categories, id: \.self) { cat in
                    catChip(cat, id: cat)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
    }

    private func catChip(_ label: String, id: String?) -> some View {
        let selected = selectedCategory == id
        return Button {
            selectedCategory = id
        } label: {
            Text(label)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? SwooshNeonTokens.Accent.cyan : SwooshNeonTokens.Canvas.text2)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(selected ? SwooshNeonTokens.Accent.cyan.opacity(0.12) : Color.white.opacity(0.03))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(
                    selected ? SwooshNeonTokens.Accent.cyan.opacity(0.3) : SwooshNeonTokens.Line.rule,
                    lineWidth: 0.5
                ))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Skill grid

    private var skillGrid: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(filteredSkills) { skill in
                    skillCard(skill)
                }
            }
            .padding(24)
        }
    }

    private func skillCard(_ skill: SkillSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "lightbulb")
                    .font(.system(size: 16))
                    .foregroundStyle(trustColor(skill.trust))
                VStack(alignment: .leading, spacing: 2) {
                    Text(skill.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                        .lineLimit(1)
                }
                Spacer()
                trustBadge(skill.trust)
            }
            Text(skill.description)
                .font(.system(size: 11))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                .lineLimit(3)

            HStack {
                Text(skill.category)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(SwooshNeonTokens.Accent.cyan)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(SwooshNeonTokens.Accent.cyan.opacity(0.1))
                    .clipShape(Capsule())
                Spacer()
                if skill.id.hasPrefix("bundled.") {
                    Text("BUNDLED")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                }
            }
        }
        .padding(14)
        .background(VoltPaper.foreground.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(SwooshNeonTokens.Line.rule, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func trustBadge(_ trust: String) -> some View {
        let color = trustColor(trust)
        Text(trust.uppercased())
            .font(.system(size: 8, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func trustColor(_ trust: String) -> Color {
        switch trust.lowercased() {
        case "frozen": return SwooshNeonTokens.Accent.cyan
        case "promoted": return VoltPaper.accent
        case "reviewed": return VoltPaper.primary
        case "draft": return VoltPaper.Chart.c4
        case "rejected": return VoltPaper.destructive
        default: return VoltPaper.mutedFg
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text("Loading skills…")
                .font(.system(size: 12))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Network

    private func loadSkills() async {
        guard let client = SwooshDaemonClient.client() else {
            errorMessage = "Daemon not reachable."
            isLoading = false
            return
        }
        isLoading = true
        do {
            let response = try await client.skills()
            skills = response.skills
            errorMessage = nil
        } catch {
            errorMessage = "Failed: \(error.localizedDescription)"
        }
        isLoading = false
    }
}


