// DetourIntegrationConnectorSetup.swift — agent-path connector setup checks (0.5A)

import Foundation

enum DetourIntegrationSetupState {
    case connected
    case savedContext
    case needsAction
    case failed
}

struct DetourIntegrationSetupResult {
    var state: DetourIntegrationSetupState
    var message: String
}

@MainActor
enum DetourIntegrationConnectorSetup {
    static func connect(
        _ item: DetourIntegrationConnection,
        store: OnboardingStore
    ) async -> DetourIntegrationSetupResult {
        store.connectIntegration(item.integration)
        materializeConnectorCredentialsIfNeeded(item, store: store)
        guard let adapterID = item.adapterID else {
            return DetourIntegrationSetupResult(state: .needsAction, message: "Open setup")
        }
        do {
            let client = try await DetourHomeDaemonClient.makeEnsuringDaemon()
            let adapters = try await client.setChatAdapter(id: adapterID, enabled: true)
            let status = try await connectorStatus(client: client, connectorID: item.connectorHealthID)
            if let connector = status.connectors.first(where: { $0.usable }) {
                return DetourIntegrationSetupResult(
                    state: .connected,
                    message: connector.liveHealth.account.map { "Connected \($0)" } ?? "Connected"
                )
            }
            if item.integration.slug == "twitter", store.hasApprovedXSessionContext {
                return DetourIntegrationSetupResult(state: .savedContext, message: "X session saved")
            }
            if let connector = status.connectors.first {
                return DetourIntegrationSetupResult(
                    state: connector.liveHealth.state == "failed" ? .failed : .needsAction,
                    message: connector.liveHealth.doctor ?? connector.liveHealth.detail
                )
            }
            if let adapter = adapters.adapters.first(where: { $0.id == adapterID }) {
                return DetourIntegrationSetupResult(
                    state: .needsAction,
                    message: missingLabel(adapter.missingCredentials)
                )
            }
            return DetourIntegrationSetupResult(state: .failed, message: "Connector not found")
        } catch {
            return DetourIntegrationSetupResult(
                state: .failed,
                message: DetourHomeDaemonClient.display(error)
            )
        }
    }

    static func test(
        _ item: DetourIntegrationConnection,
        store: OnboardingStore? = nil
    ) async -> DetourIntegrationSetupResult {
        if let store {
            materializeConnectorCredentialsIfNeeded(item, store: store)
        }
        guard item.adapterID != nil else {
            return DetourIntegrationSetupResult(state: .needsAction, message: "Open setup")
        }
        do {
            let client = try await DetourHomeDaemonClient.makeEnsuringDaemon()
            let status = try await connectorStatus(client: client, connectorID: item.connectorHealthID)
            if let connector = status.connectors.first(where: { $0.usable }) {
                return DetourIntegrationSetupResult(
                    state: .connected,
                    message: connector.liveHealth.account.map { "Verified \($0)" } ?? "Verified"
                )
            }
            if let connector = status.connectors.first {
                return DetourIntegrationSetupResult(
                    state: connector.liveHealth.state == "failed" ? .failed : .needsAction,
                    message: connector.liveHealth.doctor ?? connector.liveHealth.detail
                )
            }
            return DetourIntegrationSetupResult(
                state: status.success ? .needsAction : .failed,
                message: status.doctor.first ?? "Needs setup"
            )
        } catch {
            return DetourIntegrationSetupResult(
                state: .failed,
                message: DetourHomeDaemonClient.display(error)
            )
        }
    }

    private static func connectorStatus(
        client: SwooshAPIClient,
        connectorID: String
    ) async throws -> DetourConnectorStatusEnvelope {
        let request = DetourConnectorStatusRequest(connectorID: connectorID, includeAll: false)
        let data = try JSONEncoder.swooshDefault.encode(request)
        let args = String(data: data, encoding: .utf8) ?? "{}"
        let response = try await client.executeTool(
            name: "connector.status",
            body: ToolExecuteRequest(argsJSON: args)
        )
        if let error = response.error, !error.isEmpty {
            throw DetourIntegrationSetupError.tool(error)
        }
        guard let output = response.outputJSON,
              let outputData = output.data(using: .utf8) else {
            throw DetourIntegrationSetupError.emptyOutput
        }
        return try JSONDecoder.swooshDefault.decode(DetourConnectorStatusEnvelope.self, from: outputData)
    }

    private static func missingLabel(_ values: [String]) -> String {
        guard let first = values.first else { return "Needs setup" }
        return "Needs \(first)"
    }

    private static func materializeConnectorCredentialsIfNeeded(
        _ item: DetourIntegrationConnection,
        store: OnboardingStore
    ) {
        guard item.integration.slug == "twitter" else { return }
        _ = DetourPersonalizationRunner().exportApprovedXBrowserSessionCredentials(
            candidates: store.personalizationResult?.setupCandidates ?? [],
            approvedCandidateIDs: store.approvedSetupCandidateIDs,
            setupCandidateScopes: store.setupCandidateScopes
        )
    }
}

private struct DetourConnectorStatusRequest: Encodable {
    var connectorID: String
    var includeAll: Bool
}

private struct DetourConnectorStatusEnvelope: Decodable {
    var success: Bool
    var connectors: [DetourConnectorRuntimeStatus]
    var doctor: [String]
}

private struct DetourConnectorRuntimeStatus: Decodable {
    var usable: Bool
    var liveHealth: DetourConnectorLiveHealth
}

private struct DetourConnectorLiveHealth: Decodable {
    var state: String
    var account: String?
    var detail: String
    var doctor: String?
}

private enum DetourIntegrationSetupError: LocalizedError {
    case emptyOutput
    case tool(String)

    var errorDescription: String? {
        switch self {
        case .emptyOutput:
            return "Connector health returned no output."
        case let .tool(message):
            return message
        }
    }
}

private extension OnboardingStore {
    var hasApprovedXSessionContext: Bool {
        guard let result = personalizationResult else { return false }
        let approved = approvedSetupCandidateIDs
        return result.setupCandidates.contains { candidate in
            let isXSession = candidate.id.hasPrefix("credential.x.")
                || candidate.id == "credential.x"
                || candidate.id.hasPrefix("credential.browser-session.")
            return isXSession && (approved.contains(candidate.id) || candidate.selected)
        }
    }
}
