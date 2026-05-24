// SwooshUI/DashboardPanes/SelfImprovementDashboardPanes.swift — Goals manifesting and skills panes — 0.9U

#if os(macOS)

import SwiftUI
import SwooshClient
import SwooshConfig
import SwooshCore
import SwooshGenerativeUI
import SwooshModels
import SwooshTools

struct GoalsDashboardPane: View {
    let snapshot: DashboardRuntimeSnapshot
    @Environment(\.swooshTheme) var theme

    var body: some View {
        DashboardPane(title: "Goals", icon: "target", subtitle: "Goal runner state and iteration progress") {
            HStack(spacing: 10) {
                StatBadge(value: "\(snapshot.records?.goals.count ?? 0)", label: "Goals", tint: .cyan)
                StatBadge(value: activeCount, label: "Active", tint: .green)
            }

            PaneCard {
                Text("GOALS")
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(theme.textPrimary.opacity(0.55))
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                if let goals = snapshot.records?.goals, !goals.isEmpty {
                    ForEach(goals) { goal in
                        ListRow(
                            icon: goal.state == "completed" ? "checkmark.circle.fill" : "target",
                            iconTint: goal.state == "completed" ? .green : .cyan,
                            title: goal.statement,
                            subtitle: "Progress \(goal.progress)",
                            trailing: goal.state.capitalized
                        )
                    }
                } else {
                    emptyState(icon: "target", text: "No goals recorded yet.")
                }
            }
        }
    }

    private var activeCount: String {
        "\(snapshot.records?.goals.filter { $0.state == "active" || $0.state == "pending" }.count ?? 0)"
    }

    private func emptyState(icon: String, text: String) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 22)).foregroundStyle(theme.textPrimary.opacity(0.35))
                Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(theme.textPrimary.opacity(0.55))
            }
            Spacer()
        }
        .padding(20)
    }
}

struct ManifestingDashboardPane: View {
    let snapshot: DashboardRuntimeSnapshot
    @Environment(\.swooshTheme) var theme

    var body: some View {
        DashboardPane(title: "Manifesting", icon: "moon.stars", subtitle: "Recent background proposal passes") {
            HStack(spacing: 10) {
                StatBadge(value: "\(snapshot.records?.manifestations.count ?? 0)", label: "Passes", tint: .purple)
                StatBadge(value: "\(proposalCount)", label: "Proposals", tint: .yellow)
            }

            PaneCard {
                Text("RECENT PASSES")
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(theme.textPrimary.opacity(0.55))
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                if let rows = snapshot.records?.manifestations, !rows.isEmpty {
                    ForEach(rows) { row in
                        ListRow(
                            icon: row.status == "completed" ? "checkmark.circle.fill" : "moon.stars",
                            iconTint: row.status == "completed" ? .green : .purple,
                            title: row.triggerReason,
                            subtitle: row.summary,
                            trailing: "\(row.proposalCount)"
                        )
                    }
                } else {
                    emptyState(icon: "moon.stars", text: "No manifestation passes recorded yet.")
                }
            }
        }
    }

    private var proposalCount: Int {
        snapshot.records?.manifestations.reduce(0) { $0 + $1.proposalCount } ?? 0
    }

    private func emptyState(icon: String, text: String) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 22)).foregroundStyle(theme.textPrimary.opacity(0.35))
                Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(theme.textPrimary.opacity(0.55))
            }
            Spacer()
        }
        .padding(20)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Skills
// ═══════════════════════════════════════════════════════════════════

struct SkillsPane: View {
    let snapshot: DashboardRuntimeSnapshot
    @Environment(\.swooshTheme) var theme
    @State private var search: String = ""

    init(snapshot: DashboardRuntimeSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        DashboardPane(
            title: "Skills",
            icon: "star.fill",
            subtitle: "Skill catalog with trust state"
        ) {
            HStack(spacing: 10) {
                StatBadge(value: "\(snapshot.skills.count)", label: "Promptable", tint: .yellow)
                StatBadge(
                    value: trustCount(of: "promoted"),
                    label: "Promoted",
                    tint: .green
                )
                StatBadge(
                    value: trustCount(of: "draft"),
                    label: "Drafts",
                    tint: .orange
                )
                StatBadge(
                    value: trustCount(of: "reviewed"),
                    label: "Reviewed",
                    tint: .blue
                )
            }

            TextField("Search skills…", text: $search)
                .textFieldStyle(.roundedBorder)

            PaneCard {
                Text("PROMPTABLE SKILLS")
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(theme.textPrimary.opacity(0.55))
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                if filteredSkills.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "star")
                                .font(.system(size: 22))
                                .foregroundStyle(theme.textPrimary.opacity(0.35))
                            Text(search.isEmpty
                                 ? "No promotable skills loaded yet."
                                 : "Nothing matches “\(search)”.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(theme.textPrimary.opacity(0.55))
                        }
                        Spacer()
                    }
                    .padding(20)
                } else {
                    ForEach(filteredSkills) { skill in
                        ListRow(
                            icon: trustIcon(skill.trust),
                            iconTint: trustColor(skill.trust),
                            title: skill.title,
                            subtitle: skill.description,
                            trailing: skill.trust.capitalized,
                            trailingTint: trustColor(skill.trust)
                        )
                    }
                }
            }
        }
    }

    private var filteredSkills: [SkillSummary] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return snapshot.skills }
        return snapshot.skills.filter {
            $0.title.lowercased().contains(q) || $0.description.lowercased().contains(q)
        }
    }

    private func trustCount(of trust: String) -> String {
        let count = snapshot.skills.filter { $0.trust.lowercased() == trust }.count
        return "\(count)"
    }

    private func trustIcon(_ trust: String) -> String {
        switch trust.lowercased() {
        case "promoted": return "checkmark.seal.fill"
        case "reviewed": return "eye"
        case "draft":    return "pencil"
        case "rejected": return "xmark.circle"
        case "frozen":   return "snowflake"
        default:         return "star"
        }
    }

    private func trustColor(_ trust: String) -> Color {
        switch trust.lowercased() {
        case "promoted": return .green
        case "reviewed": return .blue
        case "draft":    return .orange
        case "rejected": return .red
        case "frozen":   return .cyan
        default:         return .secondary
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Memory Vault
// ═══════════════════════════════════════════════════════════════════

#endif
