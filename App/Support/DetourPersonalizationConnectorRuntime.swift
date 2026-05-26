// DetourPersonalizationConnectorRuntime.swift — personalization setup services (0.5A)

import Foundation

@MainActor
extension DetourPersonalizationRunner {
    func approvedHasCredential(_ approved: [DetourSetupCandidate], keys: [String]) -> Bool {
        let wanted = Set(keys)
        return approved.contains { candidate in
            guard candidate.category == .account || candidate.id.hasPrefix("credential."),
                  let credentialKeys = candidate.credentialKeys else {
                return false
            }
            return !Set(credentialKeys).isDisjoint(with: wanted)
        }
    }

    func connectorPluginSpec(candidateID: String) -> ConnectorPluginSpec {
        switch candidateID {
        case "connector.discord":
            return ConnectorPluginSpec(
                candidateID: candidateID,
                pluginID: "discord",
                displayName: "Discord",
                requiredCredentialKeys: ["DISCORD_BOT_TOKEN", "DISCORD_API_TOKEN"],
                toolNameFragments: ["discord"]
            )
        case "connector.telegram":
            return ConnectorPluginSpec(
                candidateID: candidateID,
                pluginID: "telegram",
                displayName: "Telegram",
                requiredCredentialKeys: ["TELEGRAM_BOT_TOKEN"],
                toolNameFragments: ["telegram"]
            )
        case "connector.github":
            return ConnectorPluginSpec(
                candidateID: candidateID,
                pluginID: "github",
                displayName: "GitHub",
                requiredCredentialKeys: ["GITHUB_TOKEN", "GITHUB_USER_PAT", "GITHUB_AGENT_PAT"],
                toolNameFragments: ["github", "git"]
            )
        case "connector.agentmail":
            return ConnectorPluginSpec(
                candidateID: candidateID,
                pluginID: "agentmail",
                displayName: "AgentMail",
                requiredCredentialKeys: ["AGENTMAIL_API_KEY"],
                toolNameFragments: ["agentmail", "mail"]
            )
        case "connector.imessage":
            return ConnectorPluginSpec(
                candidateID: candidateID,
                pluginID: "imessage",
                displayName: "iMessage",
                requiredCredentialKeys: [],
                toolNameFragments: ["imessage", "message"]
            )
        case "connector.x":
            return ConnectorPluginSpec(
                candidateID: candidateID,
                pluginID: "x",
                displayName: "X",
                requiredCredentialKeys: [],
                toolNameFragments: ["twitter", "x."]
            )
        case "connector.slack":
            return ConnectorPluginSpec(
                candidateID: candidateID,
                pluginID: "slack",
                displayName: "Slack",
                requiredCredentialKeys: ["SLACK_BOT_TOKEN", "SLACK_API_TOKEN"],
                toolNameFragments: ["slack"]
            )
        case "connector.linear":
            return ConnectorPluginSpec(
                candidateID: candidateID,
                pluginID: "linear",
                displayName: "Linear",
                requiredCredentialKeys: ["LINEAR_API_KEY", "LINEAR_ACCESS_TOKEN"],
                toolNameFragments: ["linear"]
            )
        default:
            let slug = candidateID
                .replacingOccurrences(of: "connector.", with: "")
                .replacingOccurrences(of: ".", with: "-")
            return ConnectorPluginSpec(
                candidateID: candidateID,
                pluginID: slug,
                displayName: slug.capitalized,
                requiredCredentialKeys: [],
                toolNameFragments: [slug]
            )
        }
    }

    func verifyConnectorRuntime(
        _ spec: ConnectorPluginSpec,
        approved: [DetourSetupCandidate],
        runtimeTools: Set<String>?
    ) -> DetourSetupApplicationItem {
        let credentialsReady = spec.requiredCredentialKeys.isEmpty
            || approvedHasCredential(approved, keys: spec.requiredCredentialKeys)
        guard credentialsReady else {
            return DetourSetupApplicationItem(
                id: "connector.\(spec.pluginID).missing-credential",
                title: "\(spec.displayName) connector",
                detail: "\(spec.displayName) is selected, but it still needs a usable credential before the agent can verify it.",
                state: .needsAction,
                doctor: "Add or approve a \(spec.displayName) credential, then run Apply setup again."
            )
        }
        guard let runtimeTools else {
            return DetourSetupApplicationItem(
                id: "connector.\(spec.pluginID).runtime-unreachable",
                title: "\(spec.displayName) connector",
                detail: "\(spec.displayName) is saved, but Detour could not reach the running agent runtime for a live check.",
                state: .needsAction,
                doctor: "Start swooshd, then run Apply setup again. Detour will call the same connector tools the agent uses."
            )
        }
        var matchingTools = Array(runtimeTools.filter { tool in
            spec.toolNameFragments.contains { fragment in
                tool.localizedCaseInsensitiveContains(fragment)
            }
        })
        if runtimeTools.contains("connector.status") {
            matchingTools.append("connector.status")
        }
        matchingTools = Array(Set(matchingTools)).sorted()
        guard !matchingTools.isEmpty else {
            return DetourSetupApplicationItem(
                id: "connector.\(spec.pluginID).missing-runtime",
                title: "\(spec.displayName) connector",
                detail: "\(spec.displayName) is saved, but the running agent runtime has no \(spec.displayName) connector tools registered.",
                state: .needsAction,
                doctor: "Install or enable the real \(spec.displayName) connector or MCP server, then run Apply setup again. Detour no longer marks placeholder tools as connected."
            )
        }
        guard let healthTool = matchingTools.first(where: isConnectorHealthTool) else {
            return DetourSetupApplicationItem(
                id: "connector.\(spec.pluginID).registered",
                title: "\(spec.displayName) connector",
                detail: "\(spec.displayName) has runtime tools registered, but none expose a status or safe list check.",
                state: .enabled,
                doctor: "Add a read-only status/list tool for \(spec.displayName) so setup can verify the connector end to end."
            )
        }
        let health = executeConnectorHealthTool(healthTool, connectorID: spec.pluginID)
        return DetourSetupApplicationItem(
            id: "connector.\(spec.pluginID).health",
            title: "\(spec.displayName) connector",
            detail: health
                ? "\(spec.displayName) answered through the live agent tool path."
                : "\(spec.displayName) is registered, but its live health check failed.",
            state: health ? .connected : .failed,
            doctor: health ? nil : "Open \(spec.displayName) connector settings, verify its credential, and run Apply setup again."
        )
    }

    func liveRuntimeToolNames() -> Set<String>? {
        guard let token = swooshAPIToken(),
              let curl = executable(named: "curl") ?? executableAtPath("/usr/bin/curl") else {
            return nil
        }
        let port = ProcessInfo.processInfo.environment["SWOOSH_PORT"]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "8787"
        guard let output = runProcessOutput(
            executable: curl,
            arguments: [
                "-sS",
                "http://127.0.0.1:\(port)/api/tools",
                "-H", "Authorization: Bearer \(token)",
            ],
            currentDirectory: Self.projectRoot
        ),
              let data = output.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tools = object["tools"] as? [[String: Any]] else {
            return nil
        }
        return Set(tools.flatMap { tool in
            [tool["name"] as? String, tool["id"] as? String].compactMap(\.self)
        })
    }

    func executeConnectorHealthTool(_ toolName: String, connectorID: String) -> Bool {
        guard let token = swooshAPIToken(),
              let curl = executable(named: "curl") ?? executableAtPath("/usr/bin/curl"),
              let bodyURL = try? writeToolExecuteRequest(toolName: toolName, connectorID: connectorID),
              let encodedToolName = toolName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return false
        }
        let port = ProcessInfo.processInfo.environment["SWOOSH_PORT"]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "8787"
        guard let output = runProcessOutput(
            executable: curl,
            arguments: [
                "-sS",
                "-X", "POST",
                "http://127.0.0.1:\(port)/api/tools/\(encodedToolName)/execute",
                "-H", "Authorization: Bearer \(token)",
                "-H", "Content-Type: application/json",
                "--data-binary", "@\(bodyURL.path)",
            ],
            currentDirectory: Self.projectRoot
        ) else {
            return false
        }
        return connectorHealthSucceeded(output, toolName: toolName)
    }

    func isConnectorHealthTool(_ name: String) -> Bool {
        let value = name.lowercased()
        return ["status", "health", "whoami", "me", "list", "read"].contains { value.contains($0) }
    }

    func connectorHealthSucceeded(_ output: String, toolName: String) -> Bool {
        guard let data = output.data(using: .utf8),
              let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              response["success"] as? Bool == true else {
            return false
        }
        guard toolName == "connector.status" else {
            return true
        }
        guard let outputJSON = response["outputJSON"] as? String,
              let outputData = outputJSON.data(using: .utf8),
              let status = try? JSONSerialization.jsonObject(with: outputData) as? [String: Any] else {
            return false
        }
        if let connectors = status["connectors"] as? [[String: Any]],
           connectors.contains(where: { $0["usable"] as? Bool == true }) {
            return true
        }
        if let states = status["stateAdapters"] as? [[String: Any]],
           states.contains(where: { ($0["enabled"] as? Bool == true) && ($0["configured"] as? Bool == true) }) {
            return true
        }
        return false
    }

    func writeToolExecuteRequest(toolName: String, connectorID: String) throws -> URL {
        let directory = fileManager.homeDirectoryForCurrentUser
            .appending(path: ".detour")
            .appending(path: "tool-health")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let argsData = try JSONSerialization.data(
            withJSONObject: ["connectorID": connectorID],
            options: [.sortedKeys]
        )
        let argsJSON = String(data: argsData, encoding: .utf8) ?? "{}"
        let payload = [
            "argsJSON": argsJSON,
            "sessionID": "detour-onboarding-\(stableIDComponent(toolName))",
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let url = directory.appending(path: "\(stableIDComponent(toolName)).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    func credentialBackedConnectorItem(
        _ candidate: DetourSetupCandidate,
        approved: [DetourSetupCandidate],
        keys: [String],
        ready: String,
        missing: String
    ) -> DetourSetupApplicationItem {
        let hasCredential = approvedHasCredential(approved, keys: keys)
        return DetourSetupApplicationItem(
            id: "setup.\(candidate.id)",
            title: candidate.title,
            detail: hasCredential ? ready : missing,
            state: hasCredential ? .enabled : .needsAction
        )
    }

    func isCredentialCandidate(_ candidate: DetourSetupCandidate) -> Bool {
        candidate.category == .account || candidate.id.hasPrefix("credential.")
    }

    func saveSetupApplicationReport(_ report: DetourSetupApplicationReport) {
        do {
            let directory = fileManager.homeDirectoryForCurrentUser.appending(path: ".detour")
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(report)
            try data.write(to: directory.appending(path: "setup-application-report.json"), options: .atomic)
        } catch {
            logger.error("[DetourPersonalizationRunner] Failed to save setup application report \(error.localizedDescription, privacy: .public)")
        }
    }
}
