// DetourOnboardingPersonalizationReview.swift — personalization candidate review surface (0.5A)

import AppKit
import QuartzCore

extension DetourOnboardingContentView {
    func renderPersonalizationReviewContent() {
        store.restoreSavedPersonalizationReportIfNeeded()
        let width = max(520, personalizationReviewScrollView.contentSize.width)
        personalizationReviewContentView.subviews.forEach { $0.removeFromSuperview() }
        let groups = filteredCandidateGroups(personalizationCandidateGroups())
        let signature = candidateReviewSignature(groups: groups)
        let shouldResetScroll = signature != personalizationReviewContentSignature
        personalizationReviewContentSignature = signature

        var y: CGFloat = 12
        let x: CGFloat = 12
        let contentWidth = width - x * 2
        for group in groups {
            addCandidateGroup(group, y: &y, width: contentWidth, x: x)
        }
        if groups.isEmpty {
            addInsightEmptyState(y: &y, width: contentWidth, x: x)
        }

        let height = max(personalizationReviewScrollView.contentSize.height, y + 12)
        personalizationReviewContentView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        if shouldResetScroll {
            personalizationReviewScrollView.contentView.scroll(to: .zero)
            personalizationReviewScrollView.reflectScrolledClipView(personalizationReviewScrollView.contentView)
        }
    }

    func personalizationCandidateGroups() -> [DetourPersonalizationCandidateGroup] {
        guard let result = store.personalizationResult else { return [] }
        let visibleCandidates = result.setupCandidates
            .filter { !store.deniedSetupCandidateIDs.contains($0.id) }
            .sortedForReview()
        var groups: [DetourPersonalizationCandidateGroup] = []
        let xCandidates = visibleCandidates.filter(isXAccountCandidate)
        if !xCandidates.isEmpty {
            groups.append(DetourPersonalizationCandidateGroup(
                title: "X accounts",
                detail: "Signed-in X accounts found in browser profiles.",
                candidates: xCandidates
            ))
        }
        let categories: [DetourSetupCategory] = [
            .account,
            .connector,
            .mcp,
            .permission,
            .model,
            .context,
            .goal,
            .schedule,
            .skill,
        ]
        groups.append(contentsOf: categories.compactMap { category in
            let candidates = visibleCandidates.filter { candidate in
                candidate.category == category && !isXAccountCandidate(candidate)
            }
            guard !candidates.isEmpty else { return nil }
            return DetourPersonalizationCandidateGroup(
                title: candidateGroupTitle(category),
                detail: candidateGroupDetail(category),
                candidates: candidates
            )
        })
        return groups
    }

    func isXAccountCandidate(_ candidate: DetourSetupCandidate) -> Bool {
        candidate.id.hasPrefix("credential.x.")
            || candidate.id == "credential.x"
            || candidate.id.hasPrefix("credential.browser-session.")
    }

    func filteredCandidateGroups(
        _ groups: [DetourPersonalizationCandidateGroup]
    ) -> [DetourPersonalizationCandidateGroup] {
        let query = setupInsightQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return groups }
        return groups.compactMap { group in
            let matches = group.candidates.filter { candidate in
                insightText(
                    candidate.title,
                    candidate.detail,
                    candidate.source,
                    candidate.category.rawValue,
                    candidate.prompt ?? "",
                    candidate.credentialProviderID ?? "",
                    candidate.credentialKeys?.joined(separator: " ") ?? ""
                ).contains(query)
            }
            guard !matches.isEmpty else { return nil }
            return DetourPersonalizationCandidateGroup(
                title: group.title,
                detail: group.detail,
                candidates: matches
            )
        }
    }

    func candidateReviewSignature(groups: [DetourPersonalizationCandidateGroup]) -> String {
        [
            setupInsightQuery,
            groups.map { group in
                let ids = group.candidates.map { candidate in
                    let scope = store.setupCandidateScopes[candidate.id]?.rawValue ?? candidate.scope?.rawValue ?? ""
                    let approved = store.approvedSetupCandidateIDs.contains(candidate.id) ? "1" : "0"
                    return "\(candidate.id):\(approved):\(scope)"
                }.joined(separator: ",")
                return "\(group.title):\(ids)"
            }.joined(separator: "|")
        ].joined(separator: "#")
    }

    func addCandidateGroup(
        _ group: DetourPersonalizationCandidateGroup,
        y: inout CGFloat,
        width: CGFloat,
        x: CGFloat
    ) {
        let titleField = NSTextField(labelWithString: "\(group.title) (\(group.candidates.count))")
        titleField.font = .systemFont(ofSize: 15, weight: .semibold)
        titleField.textColor = .white
        titleField.frame = NSRect(x: x, y: y, width: width, height: 24)
        personalizationReviewContentView.addSubview(titleField)
        y += 28

        if let detail = group.detail, !detail.isEmpty {
            addInsightCaption(detail, y: &y, width: width, x: x)
        }

        for candidate in group.candidates {
            let row = DetourPersonalizationCandidateRowView(
                candidate: candidate,
                approved: store.personalizationCandidateIsApproved(candidate),
                scope: store.personalizationCandidateScope(candidate),
                userName: store.userName,
                agentName: store.agentName
            )
            row.onApprovalChanged = { [weak self] id, approved in
                self?.store.setPersonalizationCandidateApproval(id: id, approved: approved)
                self?.reloadPersonalizationViews()
            }
            row.onScopeChanged = { [weak self] id, role in
                self?.store.setPersonalizationCandidateScope(id: id, role: role)
                self?.reloadPersonalizationViews()
            }
            row.onPermissionRequested = { [weak self] id in
                self?.openPermissionSettings(for: id)
            }
            row.frame = NSRect(x: x, y: y, width: width, height: 82)
            personalizationReviewContentView.addSubview(row)
            y += 90
        }
        y += 12
    }

    func candidateGroupTitle(_ category: DetourSetupCategory) -> String {
        switch category {
        case .account: "Accounts"
        case .connector: "Connectors"
        case .mcp: "MCP servers"
        case .permission: "Permissions"
        case .model: "Providers"
        case .context: "App and activity signals"
        case .goal: "Goals"
        case .schedule: "Schedules"
        case .skill: "Skills"
        case .identity: "Profiles"
        }
    }

    func candidateGroupDetail(_ category: DetourSetupCategory) -> String? {
        switch category {
        case .account:
            "Accounts and saved access Detour can use after you choose who they belong to."
        case .connector:
            "Apps and services Detour can connect through real runtime checks."
        case .mcp:
            "Tool servers Detour can register and test through the agent runtime."
        case .permission:
            "Mac permissions needed before Detour can use local context."
        case .model:
            "Model providers and local runtimes Detour can route through."
        case .context:
            "Local usage signals summarized without raw history."
        case .goal, .schedule:
            "Goals and routines Detour can keep in view."
        case .skill:
            "Workflow knowledge Detour can add."
        case .identity:
            "Profile context for the user and agent."
        }
    }

    func insightText(_ values: String...) -> String {
        values.joined(separator: " ").lowercased()
    }

    func addInsightCaption(_ value: String, y: inout CGFloat, width: CGFloat, x: CGFloat) {
        let field = NSTextField(labelWithString: value)
        field.font = .systemFont(ofSize: 12, weight: .medium)
        field.textColor = NSColor.white.withAlphaComponent(0.58)
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = 2
        field.cell?.wraps = true
        let height = insightTextHeight(value, width: width, font: field.font ?? .systemFont(ofSize: 12))
        field.frame = NSRect(x: x, y: y, width: width, height: height)
        personalizationReviewContentView.addSubview(field)
        y += height + 8
    }

    func addInsightEmptyState(y: inout CGFloat, width: CGFloat, x: CGFloat) {
        let text = setupInsightQuery.isEmpty ? "Nothing to review yet." : "No setup items match this search."
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 14, weight: .semibold)
        field.textColor = NSColor.white.withAlphaComponent(0.68)
        field.alignment = .center
        field.frame = NSRect(x: x, y: y + 40, width: width, height: 24)
        personalizationReviewContentView.addSubview(field)
        y += 96
    }

    func showRelationshipSetupNotice() {
        let alert = NSAlert()
        alert.messageText = "Relationship guidance comes next"
        alert.informativeText = "After setup is applied, Detour will ask how to handle important people, accounts, notifications, and voice."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func insightTextHeight(_ value: String, width: CGFloat, font: NSFont) -> CGFloat {
        let rect = (value as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return max(20, ceil(rect.height) + 2)
    }
}
