// DetourPersonalizationApplySteps.swift — SetupStep implementations for applying setup (0.5A)

import Foundation

@MainActor
protocol DetourPersonalizationApplyStep {
    var id: String { get }
    func run(context: DetourPersonalizationApplyContext) async
}

@MainActor
final class DetourPersonalizationApplyContext {
    let result: DetourPersonalizationScanResult
    let approvedCandidateIDs: Set<String>
    let deniedCandidateIDs: Set<String>
    let setupCandidateScopes: [String: DetourDelegationRole]
    let delegationProfiles: [DetourDelegationProfile]
    let progress: @MainActor (DetourSetupApplicationReport) -> Void
    let services: DetourPersonalizationRunner
    var items: [DetourSetupApplicationItem] = []

    init(
        result: DetourPersonalizationScanResult,
        approvedCandidateIDs: Set<String>,
        deniedCandidateIDs: Set<String>,
        setupCandidateScopes: [String: DetourDelegationRole],
        delegationProfiles: [DetourDelegationProfile],
        progress: @escaping @MainActor (DetourSetupApplicationReport) -> Void,
        services: DetourPersonalizationRunner
    ) {
        self.result = result
        self.approvedCandidateIDs = approvedCandidateIDs
        self.deniedCandidateIDs = deniedCandidateIDs
        self.setupCandidateScopes = setupCandidateScopes
        self.delegationProfiles = delegationProfiles
        self.progress = progress
        self.services = services
    }

    var approved: [DetourSetupCandidate] {
        result.setupCandidates.filter { approvedCandidateIDs.contains($0.id) }
    }

    var denied: [DetourSetupCandidate] {
        result.setupCandidates.filter { deniedCandidateIDs.contains($0.id) }
    }

    func publish(_ item: DetourSetupApplicationItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
        let report = DetourSetupApplicationReport(items: items, savedAt: .now)
        services.saveSetupApplicationReport(report)
        progress(report)
    }
}

struct DetourCredentialApplyStep: DetourPersonalizationApplyStep {
    let id = "credentials.apply"

    func run(context: DetourPersonalizationApplyContext) async {
        let candidates = context.approved.filter(context.services.isCredentialCandidate)
        guard !candidates.isEmpty else { return }
        context.publish(DetourSetupApplicationItem(
            id: id,
            title: "Credentials",
            detail: "Importing the selected credentials using the same provider inheritance path the agent uses.",
            state: .checking
        ))
        do {
            let result = try context.services.applyCredentialApprovals(
                result: context.result,
                approvedCandidateIDs: context.approvedCandidateIDs
            )
            context.publish(context.services.credentialApplicationItem(
                candidates,
                result: result,
                setupCandidateScopes: context.setupCandidateScopes
            ))
        } catch {
            context.publish(DetourSetupApplicationItem(
                id: id,
                title: "Credentials",
                detail: "Detour could not finish importing the selected credentials.",
                state: .failed,
                doctor: "Grant Keychain access when macOS asks, make sure the Swoosh CLI is installed, then run Apply setup again."
            ))
        }
    }
}

struct DetourAppliedSetupSaveStep: DetourPersonalizationApplyStep {
    let id = "setup.save"

    func run(context: DetourPersonalizationApplyContext) async {
        context.publish(DetourSetupApplicationItem(
            id: id,
            title: "Setup file",
            detail: "Saving selected items, removed items, relationship choices, and account ownership.",
            state: .checking
        ))
        do {
            try context.services.saveAppliedSetup(
                result: context.result,
                approvedCandidateIDs: context.approvedCandidateIDs,
                deniedCandidateIDs: context.deniedCandidateIDs,
                setupCandidateScopes: context.setupCandidateScopes,
                delegationProfiles: context.delegationProfiles
            )
            context.publish(try context.services.verifyAppliedSetup(
                result: context.result,
                approvedCandidateIDs: context.approvedCandidateIDs,
                deniedCandidateIDs: context.deniedCandidateIDs,
                setupCandidateScopes: context.setupCandidateScopes
            ))
        } catch {
            context.publish(DetourSetupApplicationItem(
                id: id,
                title: "Setup file",
                detail: "Detour could not save and verify the selected setup.",
                state: .failed,
                doctor: "Check write access to ~/.detour/applied-setup.json and available disk space, then run Apply setup again."
            ))
        }
    }
}

struct DetourConnectorToggleStep: DetourPersonalizationApplyStep {
    let id = "connectors.save"

    func run(context: DetourPersonalizationApplyContext) async {
        let connectors = context.approved.filter { $0.category == .connector }
        guard !connectors.isEmpty else { return }
        context.publish(DetourSetupApplicationItem(
            id: id,
            title: "Connectors",
            detail: "Saving connector switches before checking each connector.",
            state: .checking
        ))
        do {
            try context.services.writeChatAdapterToggles(
                candidates: context.result.setupCandidates,
                approvedCandidateIDs: context.approvedCandidateIDs
            )
            context.publish(try context.services.verifyChatAdapterToggles(
                candidates: context.result.setupCandidates,
                approvedCandidateIDs: context.approvedCandidateIDs
            ))
        } catch {
            context.publish(DetourSetupApplicationItem(
                id: id,
                title: "Connectors",
                detail: "Detour could not save and verify the selected message connectors.",
                state: .failed,
                doctor: "Check write access to ~/.swoosh/chat-adapters.json, then run Apply setup again."
            ))
        }
        for candidate in connectors.sorted(by: { $0.title < $1.title }) {
            context.publish(context.services.connectorSetupItem(candidate, approved: context.approved))
        }
    }
}

struct DetourConnectorPluginStep: DetourPersonalizationApplyStep {
    let id = "connectors.runtime"

    func run(context: DetourPersonalizationApplyContext) async {
        for item in context.services.installSelectedConnectorPlugins(
            candidates: context.result.setupCandidates,
            approvedCandidateIDs: context.approvedCandidateIDs
        ) {
            context.publish(item)
        }
    }
}

struct DetourMCPSetupStep: DetourPersonalizationApplyStep {
    let id = "mcp.runtime"

    func run(context: DetourPersonalizationApplyContext) async {
        for item in context.services.installSelectedMCPServers(
            candidates: context.result.setupCandidates,
            approvedCandidateIDs: context.approvedCandidateIDs
        ) {
            context.publish(item)
        }
    }
}

struct DetourRemovedSetupStep: DetourPersonalizationApplyStep {
    let id = "setup.removed"

    func run(context: DetourPersonalizationApplyContext) async {
        let removed = context.denied.filter {
            $0.category == .connector
                || $0.category == .model
                || $0.category == .mcp
                || $0.category == .skill
                || context.services.isCredentialCandidate($0)
        }
        for candidate in removed.sorted(by: { $0.title < $1.title }) {
            context.publish(DetourSetupApplicationItem(
                id: "removed.\(candidate.id)",
                title: candidate.title,
                detail: "Removed from this setup. Detour will not use it unless you add it back later.",
                state: .removed
            ))
        }
    }
}
