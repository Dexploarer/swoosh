// DetourSetupInsightProjection.swift — read-only setup insight builder (0.5A)

import Foundation

struct DetourSetupInsightProjectionInput {
    var result: DetourPersonalizationScanResult?
    var approvedCandidateIDs: Set<String>
    var deniedCandidateIDs: Set<String>
    var setupCandidateScopes: [String: DetourDelegationRole]
    var report: DetourSetupApplicationReport?
    var userName: String
    var agentName: String
}

enum DetourSetupInsightProjection {
    static func snapshot(_ input: DetourSetupInsightProjectionInput) -> DetourSetupInsightSnapshot {
        var sections: [DetourSetupInsightSection] = []
        appendReport(input.report, to: &sections)
        if let result = input.result {
            appendCandidates(result.setupCandidates, input: input, to: &sections)
            appendRelationshipItems(result.relationshipCandidates, to: &sections)
        }
        let ordered = mergedSections(sections)
            .map { section in
                DetourSetupInsightSection(
                    id: section.id,
                    title: section.title,
                    detail: section.detail,
                    items: section.items.sorted { insightSortKey($0) < insightSortKey($1) }
                )
            }
            .filter { !$0.items.isEmpty }
            .sorted { categoryOrder($0.id) < categoryOrder($1.id) }
        return DetourSetupInsightSnapshot(sections: ordered, summary: summary(ordered))
    }

    private static func appendReport(
        _ report: DetourSetupApplicationReport?,
        to sections: inout [DetourSetupInsightSection]
    ) {
        guard let report else { return }
        let items = report.items.enumerated().compactMap { index, item -> DetourSetupInsightItem? in
            guard item.state != .removed else { return nil }
            let publicID = "report.\(index)"
            return DetourSetupInsightItem(
                id: publicID,
                category: .setupChecks,
                title: DetourSetupInsightRedaction.display(item.title),
                detail: DetourSetupInsightRedaction.display(item.detail),
                sourceLabel: nil,
                owner: .shared,
                status: insightStatus(from: item),
                doctor: item.doctor.map(DetourSetupInsightRedaction.display),
                count: nil,
                actions: item.doctor == nil ? [] : [action(.openDoctor, "Doctor", publicID)]
            )
        }
        sections.append(section(.setupChecks, items: items))
    }

    private static func appendCandidates(
        _ candidates: [DetourSetupCandidate],
        input: DetourSetupInsightProjectionInput,
        to sections: inout [DetourSetupInsightSection]
    ) {
        var grouped: [DetourSetupInsightCategory: [DetourSetupInsightItem]] = [:]
        for rawGroup in candidateGroups(candidates) {
            let visibleCandidates = rawGroup.candidates.filter { !shouldHideCandidate($0) }
            guard let candidate = visibleCandidates.first else { continue }
            let group = DetourSetupInsightCandidateGroup(publicID: rawGroup.publicID, candidates: visibleCandidates)
            let denied = group.candidates.allSatisfy { input.deniedCandidateIDs.contains($0.id) }
            guard !denied else { continue }
            let publicID = group.publicID
            let category = insightCategory(candidate)
            let role = groupRole(group, input: input)
            let owner = DetourSetupInsightRedaction.owner(from: role, category: candidate.category)
            let approved = group.candidates.contains { input.approvedCandidateIDs.contains($0.id) || $0.selected }
            grouped[category, default: []].append(DetourSetupInsightItem(
                id: publicID,
                category: category,
                title: groupTitle(group),
                detail: groupDetail(group, owner: owner, input: input),
                sourceLabel: sourceLabel(candidate),
                owner: owner,
                status: candidateStatus(candidate, approved: approved, denied: denied, role: role),
                doctor: nil,
                count: group.candidates.count > 1 ? group.candidates.count : candidate.foundCount,
                actions: candidateActions(candidate, approved: approved, publicID: publicID)
            ))
        }
        for category in DetourSetupInsightCategory.allCases {
            if let items = grouped[category], !items.isEmpty {
                sections.append(section(category, items: items))
            }
        }
    }

    private static func appendRelationshipItems(
        _ relationships: [DetourRelationshipCandidate],
        to sections: inout [DetourSetupInsightSection]
    ) {
        let items = relationships.prefix(24).enumerated().map { index, relationship in
            let publicID = "relationship.\(index)"
            return DetourSetupInsightItem(
                id: publicID,
                category: .relationships,
                title: DetourSetupInsightRedaction.display(relationship.displayName),
                detail: relationshipDetail(relationship),
                sourceLabel: DetourSetupInsightRedaction.display(relationship.source),
                owner: .user,
                status: relationship.selected ? .using : .pending,
                doctor: nil,
                count: relationship.messageCount,
                actions: [action(.openRelationshipQA, "Discuss", publicID)]
            )
        }
        if !items.isEmpty {
            sections.append(section(.relationships, items: items))
        }
    }

    private static func section(
        _ category: DetourSetupInsightCategory,
        items: [DetourSetupInsightItem]
    ) -> DetourSetupInsightSection {
        DetourSetupInsightSection(
            id: category.rawValue,
            title: category.label,
            detail: DetourSetupInsightCopy.sectionDetail(category),
            items: items
        )
    }

    private static func insightCategory(_ candidate: DetourSetupCandidate) -> DetourSetupInsightCategory {
        if candidate.id.hasPrefix("credential.x.") || candidate.id.hasPrefix("credential.browser-session.") {
            return .accounts
        }
        if candidate.id.hasPrefix("credential.") { return .credentials }
        switch candidate.category {
        case .connector, .skill:
            return .connectors
        case .mcp:
            return .mcpServers
        case .permission:
            return .permissions
        case .goal, .schedule:
            return .goalsSchedules
        case .model:
            return .providers
        case .account, .identity:
            return .accounts
        case .context:
            return .appActivitySignals
        }
    }

    private static func shouldHideCandidate(_ candidate: DetourSetupCandidate) -> Bool {
        let value = text(candidate)
        return candidate.id.hasPrefix("credential.keychain.discord") && value.contains("safe storage")
    }

    private static func candidateStatus(
        _ candidate: DetourSetupCandidate,
        approved: Bool,
        denied: Bool,
        role: DetourDelegationRole?
    ) -> DetourSetupInsightStatus {
        if denied { return .removed }
        if candidateNeedsPermission(candidate) { return .needsPermission }
        if candidateNeedsScope(candidate) && role == nil { return .needsConfiguration }
        return approved || candidate.selected ? .selected : .pending
    }

    private static func candidateActions(
        _ candidate: DetourSetupCandidate,
        approved: Bool,
        publicID: String
    ) -> [DetourSetupInsightAction] {
        var actions: [DetourSetupInsightAction] = [
            action(approved ? .remove : .use, approved ? "Remove" : "Use", publicID)
        ]
        if candidateNeedsScope(candidate) {
            actions.append(action(.scopeUser, "As me", publicID))
            actions.append(action(.scopeAgent, "As agent", publicID))
        }
        if candidateNeedsPermission(candidate) {
            actions.append(action(.grantPermission, permissionTitle(candidate), publicID))
        }
        if candidateNeedsConfigurationInput(candidate) {
            actions.append(action(.configure, "Configure", publicID))
        }
        return actions
    }

    private static func candidateNeedsScope(_ candidate: DetourSetupCandidate) -> Bool {
        candidate.scope != nil
            || candidate.prompt != nil
            || candidate.credentialProviderID != nil
            || candidate.credentialKeys?.isEmpty == false
            || candidate.id.hasPrefix("credential.")
    }

    private static func candidateNeedsPermission(_ candidate: DetourSetupCandidate) -> Bool {
        let text = text(candidate)
        if candidate.id == "context.contacts" { return true }
        return (candidate.category == .permission || candidate.id == "connector.imessage" || candidate.id == "context.messages")
            && (text.contains("full disk access") || text.contains("permission") || text.contains("grant"))
    }

    private static func candidateNeedsConfigurationInput(_ candidate: DetourSetupCandidate) -> Bool {
        !candidate.id.hasPrefix("credential.")
            && candidate.credentialKeys?.isEmpty == false
    }

    private static func title(_ candidate: DetourSetupCandidate) -> String {
        DetourSetupInsightRedaction.display(candidate.title)
    }

    private static func detail(
        _ candidate: DetourSetupCandidate,
        owner: DetourSetupInsightOwner,
        input: DetourSetupInsightProjectionInput
    ) -> String {
        let ownerLabel = DetourSetupInsightRedaction.ownerLabel(
            owner,
            userName: input.userName,
            agentName: input.agentName
        )
        let base = DetourSetupInsightRedaction.display(candidate.detail)
        if candidateNeedsScope(candidate) {
            return "\(base) Owner: \(ownerLabel)."
        }
        return base
    }

    private static func sourceLabel(_ candidate: DetourSetupCandidate) -> String? {
        let value = DetourSetupInsightRedaction.display(candidate.source)
        return value.isEmpty ? nil : value
    }

    private static func relationshipDetail(_ relationship: DetourRelationshipCandidate) -> String {
        let count = relationship.messageCount.map { "\($0) messages" }
        return [
            count,
            relationship.lastSeenDescription.map(DetourSetupInsightRedaction.display),
            relationship.tags.isEmpty ? nil : DetourSetupInsightRedaction
                .displayList(Array(relationship.tags.prefix(4)))
                .joined(separator: ", ")
        ].compactMap(\.self).joined(separator: " · ")
    }

    private static func summary(_ sections: [DetourSetupInsightSection]) -> DetourSetupCapabilitySummary {
        let items = sections.flatMap(\.items)
        let verified = items.filter { $0.status == .verified }.count
        let using = items.filter { $0.status == .using || $0.status == .selected }.count
        let pending = items.filter { $0.status == .pending }.count
        let blocked = items.filter { [.blocked, .failed, .needsPermission, .needsConfiguration].contains($0.status) }.count
        let removed = items.filter { $0.status == .removed }.count
        let unknown = items.filter { $0.status == .unknown }.count
        return DetourSetupCapabilitySummary(
            verified: verified,
            using: using,
            pending: pending,
            blocked: blocked,
            removed: removed,
            unknown: unknown,
            chartPoints: [
                chartPoint("verified", "Verified", verified, .verified),
                chartPoint("selected", "Selected", using, .selected),
                chartPoint("pending", "Pending", pending, .pending),
                chartPoint("attention", "Needs attention", blocked, .blocked),
                chartPoint("removed", "Not using", removed, .removed),
                chartPoint("unknown", "Unknown", unknown, .unknown),
            ].filter { $0.value > 0 }
        )
    }

    private static func chartPoint(
        _ id: String,
        _ label: String,
        _ count: Int,
        _ status: DetourSetupInsightStatus
    ) -> DetourSetupInsightChartPoint {
        DetourSetupInsightChartPoint(
            id: id,
            label: label,
            value: Double(count),
            category: .capabilitySummary,
            status: status
        )
    }

    private static func action(
        _ kind: DetourSetupInsightActionKind,
        _ title: String,
        _ targetID: String
    ) -> DetourSetupInsightAction {
        DetourSetupInsightAction(kind: kind, title: title, targetID: targetID)
    }

    private static func text(_ candidate: DetourSetupCandidate) -> String {
        [candidate.id, candidate.title, candidate.detail, candidate.source, candidate.category.rawValue]
            .joined(separator: " ")
            .lowercased()
    }

    private static func permissionTitle(_ candidate: DetourSetupCandidate) -> String {
        candidate.id.contains("agentmail") ? "Configure" : "Grant Access"
    }

    private static func insightSortKey(_ item: DetourSetupInsightItem) -> String {
        "\(statusOrder(item.status))|\(item.title.lowercased())|\(item.id)"
    }

    private static func statusOrder(_ status: DetourSetupInsightStatus) -> Int {
        switch status {
        case .failed:
            return 0
        case .blocked, .needsPermission, .needsConfiguration:
            return 1
        case .pending:
            return 2
        case .selected:
            return 3
        case .using:
            return 4
        case .verified:
            return 5
        case .removed:
            return 6
        case .unknown:
            return 7
        }
    }

    private static func categoryOrder(_ id: String) -> Int {
        DetourSetupInsightCategory.allCases.firstIndex { $0.rawValue == id } ?? Int.max
    }

}
