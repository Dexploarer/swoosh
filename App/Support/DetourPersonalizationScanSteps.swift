// DetourPersonalizationScanSteps.swift — SetupStep implementations for scanning (0.5A)

import Foundation

@MainActor
protocol DetourPersonalizationScanStep {
    var id: String { get }
    func run(context: DetourPersonalizationScanContext) async
}

@MainActor
final class DetourPersonalizationScanContext {
    let agentName: String
    let userName: String
    let consent: DetourCredentialInheritanceConsent
    let logURL: URL
    let logHandle: FileHandle?
    let progress: @MainActor (DetourPersonalizationProgress) -> Void
    let services: DetourPersonalizationRunner
    var scoutSucceeded = false
    var agentContextSucceeded = false
    var credentialInheritanceSucceeded = false
    var result: DetourPersonalizationScanResult?

    init(
        agentName: String,
        userName: String,
        consent: DetourCredentialInheritanceConsent,
        logURL: URL,
        progress: @escaping @MainActor (DetourPersonalizationProgress) -> Void,
        services: DetourPersonalizationRunner
    ) {
        self.agentName = agentName
        self.userName = userName
        self.consent = consent
        self.logURL = logURL
        self.logHandle = FileHandle(forWritingAtPath: logURL.path)
        self.progress = progress
        self.services = services
    }
}

struct DetourCredentialInheritanceScanStep: DetourPersonalizationScanStep {
    let id = "credentials.inherit"

    func run(context: DetourPersonalizationScanContext) async {
        guard context.consent.keychainCredentials || context.consent.browserCookies,
              let logHandle = context.logHandle else {
            return
        }
        do {
            try await context.services.runCredentialInheritance(
                consent: context.consent,
                logHandle: logHandle,
                onProgress: context.progress
            )
            context.credentialInheritanceSucceeded = true
        } catch {
            context.services.logger.error("[DetourPersonalizationSetupGraph] Credential inheritance failed \(error.localizedDescription, privacy: .public)")
        }
    }
}

struct DetourScoutScanStep: DetourPersonalizationScanStep {
    let id = "scout.scan"

    func run(context: DetourPersonalizationScanContext) async {
        guard let logHandle = context.logHandle else { return }
        do {
            try await context.services.runScout(logHandle: logHandle, onProgress: context.progress)
            context.scoutSucceeded = true
        } catch {
            context.services.logger.error("[DetourPersonalizationSetupGraph] Scout failed \(error.localizedDescription, privacy: .public)")
        }
    }
}

struct DetourAgentContextScanStep: DetourPersonalizationScanStep {
    let id = "agent-context.scan"

    func run(context: DetourPersonalizationScanContext) async {
        guard let logHandle = context.logHandle else { return }
        do {
            try await context.services.runAgentContext(logHandle: logHandle, onProgress: context.progress)
            context.agentContextSucceeded = true
        } catch {
            context.services.logger.error("[DetourPersonalizationSetupGraph] agent-context failed \(error.localizedDescription, privacy: .public)")
        }
    }
}

struct DetourInventoryScanStep: DetourPersonalizationScanStep {
    let id = "local.inventory"

    func run(context: DetourPersonalizationScanContext) async {
        let services = context.services
        await services.setProgress(0.84, "Reading apps", context.progress)
        let apps = services.appInventory()
        await services.setProgress(0.86, "Reading usage", context.progress)
        let appUsage = context.consent.appUsage ? services.appUsageInventory() : AppUsageInventory.notRequested
        await services.setProgress(0.88, "Reading repos", context.progress)
        let git = context.consent.gitHistory ? services.gitActivityInventory() : GitActivityInventory.notRequested
        await services.setProgress(0.9, "Reading contacts", context.progress)
        let contacts = await services.contactInventory(allowed: context.consent.contacts)
        await services.setProgress(0.92, "Checking accounts", context.progress)
        let messages = services.messageInventory(allowed: context.consent.messages)
        let auth = services.authInventory(
            consent: context.consent,
            installedApps: apps.names,
            userName: context.userName,
            git: git,
            providerLogURL: context.logURL
        )
        let result = services.buildResult(
            agentName: context.agentName,
            userName: context.userName,
            apps: apps,
            appUsage: appUsage,
            git: git,
            contacts: contacts,
            messages: messages,
            auth: auth,
            agentContextSignals: services.agentContextSignals(),
            scoutSucceeded: context.scoutSucceeded,
            agentContextSucceeded: context.agentContextSucceeded,
            credentialInheritanceSucceeded: context.credentialInheritanceSucceeded
        )
        services.saveReport(result)
        context.result = result
        await services.setProgress(1, "Ready", context.progress)
    }
}
