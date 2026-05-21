// SwooshUI/SkillManager/SkillsView.swift — 0.9R Manage Skills surface
//
// Mirrors the PocketPal "Manage Skills" UX shape adapted to Swoosh's trust
// model. Each skill renders as a neon tile carrying:
//   • TRUST · <state>  — uppercase eyebrow showing whether the skill is in
//     prompt (.reviewed | .promoted | .frozen) or sitting in the inbox
//     (.draft | .rejected). The agent never sees drafts.
//   • Title (the human display name) + Description.
//   • The promotable-toggle: on = SkillTrust.promoted; off = SkillTrust.draft.
//   • A "view" pill for detail.
//
// Consumes `SkillStoring` directly so any concrete store (`FileSkillStore`,
// an ActantDB-backed store, an in-memory test store) plugs in. Pure SwiftUI;
// no kernel deps.

import SwiftUI
import SwooshGenerativeUI
import SwooshSkills

public struct SkillsView: View {

    // MARK: - Inputs

    public let store: any SkillStoring

    /// Hook for "view detail" tap. Caller decides whether to push a sheet,
    /// route to a window, or noop in previews.
    public var onView: (SkillDocument) -> Void

    /// Hook for "add skill from URL" affordance in the header.
    public var onAdd: () -> Void

    public init(
        store: any SkillStoring,
        onView: @escaping (SkillDocument) -> Void = { _ in },
        onAdd: @escaping () -> Void = {}
    ) {
        self.store = store
        self.onView = onView
        self.onAdd = onAdd
    }

    // MARK: - State

    @State private var skills: [SkillDocument] = []
    @State private var query: String = ""
    @State private var loadError: String?

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SwooshNeonTokens.Spacing.base * 2) {
            header
            searchBar
            list
        }
        .padding(SwooshNeonTokens.Spacing.base * 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SwooshNeonTokens.Canvas.bg)
        .task { await load() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SKILLS")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                Text(summaryLine)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text2)
            }
            Spacer()
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SwooshNeonTokens.Accent.cyan)
                    .frame(width: 32, height: 32)
                    .neonTile(.cyan, state: .idle, shape: .card)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: SwooshNeonTokens.Spacing.micro) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            TextField("Search skills", text: $query)
                .textFieldStyle(.plain)
                .foregroundStyle(SwooshNeonTokens.Canvas.text1)
        }
        .padding(.horizontal, SwooshNeonTokens.Spacing.base + 2)
        .padding(.vertical, SwooshNeonTokens.Spacing.micro + 2)
        .neonTile(.cyan, state: .idle, shape: .card)
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        if let loadError {
            errorRow(loadError)
        } else if filtered.isEmpty {
            emptyRow
        } else {
            ScrollView {
                LazyVStack(spacing: SwooshNeonTokens.Spacing.base + 2) {
                    ForEach(filtered) { skill in
                        SkillRow(
                            skill: skill,
                            onView: { onView(skill) },
                            onTrustChange: { newTrust in
                                Task { await setTrust(skill: skill, to: newTrust) }
                            }
                        )
                    }
                }
            }
        }
    }

    private func errorRow(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(SwooshNeonTokens.Canvas.text2)
            .padding(SwooshNeonTokens.Spacing.base * 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .neonTile(.gold, state: .focus, shape: .card)
    }

    private var emptyRow: some View {
        Text("No skills match \"\(query)\"")
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            .padding(SwooshNeonTokens.Spacing.base * 2)
    }

    // MARK: - Derived

    private var filtered: [SkillDocument] {
        guard !query.isEmpty else { return skills }
        let q = query.lowercased()
        return skills.filter { s in
            s.title.lowercased().contains(q) ||
            s.id.lowercased().contains(q) ||
            s.description.lowercased().contains(q)
        }
    }

    private var summaryLine: String {
        let promoted = skills.filter { SkillTrust.promptable.contains($0.trust) }.count
        let drafts = skills.filter { $0.trust == .draft }.count
        return "\(promoted) active · \(drafts) drafts"
    }

    // MARK: - Actions

    private func load() async {
        do {
            skills = try await store.listAll()
            loadError = nil
        } catch {
            loadError = "Couldn't load skills: \(error.localizedDescription)"
        }
    }

    private func setTrust(skill: SkillDocument, to trust: SkillTrust) async {
        var updated = skill
        updated.trust = trust
        do {
            try await store.update(updated)
            await load()
        } catch {
            loadError = "Couldn't update trust: \(error.localizedDescription)"
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Skill row
// ═══════════════════════════════════════════════════════════════════

private struct SkillRow: View {
    let skill: SkillDocument
    let onView: () -> Void
    let onTrustChange: (SkillTrust) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SwooshNeonTokens.Spacing.micro) {

            // Eyebrow + toggle row
            HStack(alignment: .center) {
                Text("TRUST · \(skill.trust.rawValue.uppercased())")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                Spacer()
                Toggle(
                    "",
                    isOn: Binding(
                        get: { SkillTrust.promptable.contains(skill.trust) },
                        set: { isOn in onTrustChange(isOn ? .promoted : .draft) }
                    )
                )
                .labelsHidden()
                .tint(SwooshNeonTokens.Accent.cyan)
            }

            // Title + description
            Text(skill.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SwooshNeonTokens.Canvas.text1)
            Text(skill.description)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                .lineLimit(3)

            // Footer: identity strip + action
            HStack(spacing: SwooshNeonTokens.Spacing.base) {
                Text(skill.id)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                Spacer()
                Button(action: onView) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                        Text("view")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SwooshNeonTokens.Accent.cyan)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .padding(SwooshNeonTokens.Spacing.base * 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .neonTile(.cyan, state: .idle, shape: .card)
    }
}
