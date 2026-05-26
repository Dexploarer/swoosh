// DetourPersonalizationSetupGraph.swift — graph-owned personalization setup (0.5A)

import Foundation

@MainActor
struct DetourPersonalizationSetupGraph {
    let services: DetourPersonalizationRunner

    init(services: DetourPersonalizationRunner = DetourPersonalizationRunner()) {
        self.services = services
    }

    func scan(
        agentName: String,
        userName: String,
        credentialConsent: DetourCredentialInheritanceConsent,
        onProgress: @escaping @MainActor (DetourPersonalizationProgress) -> Void
    ) async -> DetourPersonalizationScanResult {
        let context = DetourPersonalizationScanContext(
            agentName: agentName,
            userName: userName,
            consent: credentialConsent,
            logURL: services.prepareLogURL(),
            progress: onProgress,
            services: services
        )
        defer { try? context.logHandle?.close() }
        await services.setProgress(0.08, "Starting", onProgress)
        let steps: [any DetourPersonalizationScanStep] = [
            DetourCredentialInheritanceScanStep(),
            DetourScoutScanStep(),
            DetourAgentContextScanStep(),
            DetourInventoryScanStep(),
        ]
        for step in steps {
            await step.run(context: context)
        }
        return context.result ?? DetourPersonalizationScanResult.empty(agentName: agentName, userName: userName)
    }

    func apply(
        result: DetourPersonalizationScanResult,
        approvedCandidateIDs: Set<String>,
        deniedCandidateIDs: Set<String>,
        setupCandidateScopes: [String: DetourDelegationRole],
        delegationProfiles: [DetourDelegationProfile],
        onProgress: @escaping @MainActor (DetourSetupApplicationReport) -> Void
    ) async -> DetourSetupApplicationReport {
        let context = DetourPersonalizationApplyContext(
            result: result,
            approvedCandidateIDs: approvedCandidateIDs,
            deniedCandidateIDs: deniedCandidateIDs,
            setupCandidateScopes: setupCandidateScopes,
            delegationProfiles: delegationProfiles,
            progress: onProgress,
            services: services
        )
        let steps: [any DetourPersonalizationApplyStep] = [
            DetourCredentialApplyStep(),
            DetourAppliedSetupSaveStep(),
            DetourConnectorToggleStep(),
            DetourConnectorPluginStep(),
            DetourMCPSetupStep(),
            DetourRemovedSetupStep(),
        ]
        for step in steps {
            await step.run(context: context)
        }
        if context.items.isEmpty {
            context.publish(DetourSetupApplicationItem(
                id: "setup.none",
                title: "Setup",
                detail: "No credentials or connectors were selected.",
                state: .removed
            ))
        }
        let report = DetourSetupApplicationReport(items: context.items, savedAt: .now)
        services.saveSetupApplicationReport(report)
        return report
    }

    func calibrationQuestions(
        result: DetourPersonalizationScanResult,
        approvedCandidateIDs: Set<String>,
        setupCandidateScopes: [String: DetourDelegationRole],
        userName: String,
        agentName: String
    ) -> [String] {
        services.calibrationQuestions(
            result: result,
            approvedCandidateIDs: approvedCandidateIDs,
            setupCandidateScopes: setupCandidateScopes,
            userName: userName,
            agentName: agentName
        )
    }

    func saveCalibration(
        result: DetourPersonalizationScanResult,
        approvedCandidateIDs: Set<String>,
        setupCandidateScopes: [String: DetourDelegationRole],
        delegationProfiles: [DetourDelegationProfile],
        userName: String,
        agentName: String,
        answers: [String]
    ) throws {
        try services.saveCalibration(
            result: result,
            approvedCandidateIDs: approvedCandidateIDs,
            setupCandidateScopes: setupCandidateScopes,
            delegationProfiles: delegationProfiles,
            userName: userName,
            agentName: agentName,
            answers: answers
        )
    }
}

extension DetourPersonalizationScanResult {
    static func empty(agentName: String, userName: String) -> DetourPersonalizationScanResult {
        DetourPersonalizationScanResult(
            summary: userName.isEmpty ? "\(agentName) matched installed apps only." : "\(agentName) matched installed apps only. For \(userName).",
            signals: [],
            accessItems: [],
            accounts: [],
            goals: [],
            schedules: [],
            plugins: [],
            questions: [],
            setupCandidates: [],
            relationshipCandidates: [],
            delegationProfiles: [],
            completedAt: .now,
            scoutSucceeded: false,
            agentContextSucceeded: false,
            credentialInheritanceSucceeded: false
        )
    }
}
