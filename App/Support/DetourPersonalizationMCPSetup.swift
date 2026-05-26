// DetourPersonalizationMCPSetup.swift — personalization setup services (0.5A)

import Foundation

@MainActor
extension DetourPersonalizationRunner {
    func installSelectedMCPServers(
        candidates: [DetourSetupCandidate],
        approvedCandidateIDs: Set<String>
    ) -> [DetourSetupApplicationItem] {
        let approved = candidates.filter { approvedCandidateIDs.contains($0.id) }
        let specs = approved
            .filter { $0.category == .mcp }
            .compactMap { mcpServerSpec(candidateID: $0.id) }
            .sorted { $0.displayName < $1.displayName }
        guard !specs.isEmpty else { return [] }
        do {
            try writeMCPServerProfiles(specs)
        } catch {
            logger.error("[DetourPersonalizationRunner] MCP profile write failed \(error.localizedDescription, privacy: .public)")
            return specs.map { spec in
                DetourSetupApplicationItem(
                    id: "mcp.\(spec.serverID).failed",
                    title: "\(spec.displayName) MCP server",
                    detail: "Detour could not save the MCP server profile.",
                    state: .failed
                )
            }
        }
        let hotRegistered = hotRegisterMCPServerProfiles(specs)
        return specs.map { spec in
            let ready = spec.requiredCredentialKeys.isEmpty || approvedHasCredential(approved, keys: spec.requiredCredentialKeys)
            let toolCount = hotRegistered.contains(spec.serverID) ? mcpServerToolCount(spec) : nil
            let hasRuntimeTools = (toolCount ?? 0) > 0
            return DetourSetupApplicationItem(
                id: "mcp.\(spec.serverID).configured",
                title: "\(spec.displayName) MCP server",
                detail: !ready
                    ? "\(spec.displayName) was saved, but it still needs \(spec.missingCredentialDescription) before the tools can connect."
                    : hasRuntimeTools
                    ? "\(spec.displayName) was saved, registered with the running MCP runtime, and reported \(toolCount ?? 0) tools."
                    : hotRegistered.contains(spec.serverID)
                    ? "\(spec.displayName) was saved and registered, but the runtime has not discovered usable tools yet."
                    : "\(spec.displayName) was saved, but Detour could not reach the running MCP runtime for a live check.",
                state: ready && hasRuntimeTools ? .connected : .needsAction,
                doctor: ready && hasRuntimeTools
                    ? nil
                    : !ready
                    ? "Add \(spec.missingCredentialDescription), then run Apply setup again."
                    : hotRegistered.contains(spec.serverID)
                    ? "Restart swooshd or reconnect this MCP server so it can perform tools/list discovery."
                    : "Start swooshd and run Apply setup again so Detour can register and check this MCP server live."
            )
        }
    }

    func mcpServerSpec(candidateID: String) -> DetourMCPServerSpec? {
        switch candidateID {
        case "mcp.agentmail":
            return DetourMCPServerSpec(
                candidateID: candidateID,
                serverID: "agentmail",
                displayName: "AgentMail",
                detail: "Agent-owned inbox tools for messages, threads, drafts, and replies.",
                transport: "http",
                environmentSecretRefs: [:],
                baseURL: "https://mcp.agentmail.to/mcp",
                authorizationSecretRef: "agentmail.api_key",
                localOnly: false,
                requiredCredentialKeys: ["AGENTMAIL_API_KEY"],
                missingCredentialDescription: "an AgentMail API key"
            )
        case "mcp.github":
            return DetourMCPServerSpec(
                candidateID: candidateID,
                serverID: "github",
                displayName: "GitHub",
                detail: "Repo, issue, pull request, and code-search tools.",
                command: "npx",
                arguments: ["-y", "@modelcontextprotocol/server-github"],
                environmentSecretRefs: ["GITHUB_PERSONAL_ACCESS_TOKEN": "github.user_pat"],
                requiredCredentialKeys: ["GITHUB_TOKEN", "GITHUB_USER_PAT"],
                missingCredentialDescription: "a GitHub token"
            )
        case "mcp.slack":
            return DetourMCPServerSpec(
                candidateID: candidateID,
                serverID: "slack",
                displayName: "Slack",
                detail: "Workspace tools for channels, messages, threads, reactions, and users.",
                command: "npx",
                arguments: ["-y", "@modelcontextprotocol/server-slack"],
                environmentSecretRefs: [
                    "SLACK_BOT_TOKEN": "slack.bot_token",
                    "SLACK_TEAM_ID": "slack.team_id",
                    "SLACK_CHANNEL_IDS": "slack.channel_ids",
                ],
                requiredCredentialKeys: ["SLACK_BOT_TOKEN", "SLACK_API_TOKEN"],
                missingCredentialDescription: "a Slack bot token and team ID"
            )
        case "mcp.notion":
            return DetourMCPServerSpec(
                candidateID: candidateID,
                serverID: "notion",
                displayName: "Notion",
                detail: "Workspace tools for pages, databases, comments, and search.",
                command: "npx",
                arguments: ["-y", "@notionhq/notion-mcp-server"],
                environmentSecretRefs: ["NOTION_TOKEN": "notion.token"],
                requiredCredentialKeys: ["NOTION_TOKEN", "NOTION_API_KEY"],
                missingCredentialDescription: "a Notion integration token"
            )
        case "mcp.linear":
            return DetourMCPServerSpec(
                candidateID: candidateID,
                serverID: "linear",
                displayName: "Linear",
                detail: "Issue, project, and team tools for Linear workspaces.",
                command: "npx",
                arguments: ["-y", "linear-mcp"],
                environmentSecretRefs: ["LINEAR_ACCESS_TOKEN": "linear.api_key"],
                requiredCredentialKeys: ["LINEAR_API_KEY", "LINEAR_ACCESS_TOKEN"],
                missingCredentialDescription: "a Linear API key"
            )
        default:
            return nil
        }
    }

    func writeMCPServerProfiles(_ specs: [DetourMCPServerSpec]) throws {
        let url = fileManager.homeDirectoryForCurrentUser
            .appending(path: ".swoosh")
            .appending(path: "mcp")
            .appending(path: "servers.json")
        let existing: [DetourMCPServerProfile]
        if fileManager.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            existing = try JSONDecoder().decode([DetourMCPServerProfile].self, from: data)
        } else {
            existing = []
        }
        var profiles = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for spec in specs {
            profiles[spec.serverID] = mcpServerProfile(spec, existing: profiles[spec.serverID])
        }
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(profiles.values.sorted { $0.name < $1.name })
        try data.write(to: url, options: .atomic)
    }

    func hotRegisterMCPServerProfiles(_ specs: [DetourMCPServerSpec]) -> Set<String> {
        guard let token = swooshAPIToken(),
              let curl = executable(named: "curl") ?? executableAtPath("/usr/bin/curl") else {
            return []
        }
        let port = ProcessInfo.processInfo.environment["SWOOSH_PORT"]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "8787"
        let host = "127.0.0.1"
        var registered = Set<String>()
        for spec in specs {
            guard let bodyURL = try? writeMCPCreateRequest(spec) else { continue }
            let encodedServerID = spec.serverID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? spec.serverID
            let output = runProcessOutput(
                executable: curl,
                arguments: [
                    "-sS",
                    "-o", "/dev/null",
                    "-w", "%{http_code}",
                    "-X", "POST",
                    "http://\(host):\(port)/api/mcp/servers",
                    "-H", "Authorization: Bearer \(token)",
                    "-H", "Content-Type: application/json",
                    "--data-binary", "@\(bodyURL.path)",
                ],
                currentDirectory: Self.projectRoot
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
            if output == "200" || output == "201" {
                registered.insert(spec.serverID)
                continue
            }
            let connectOutput = runProcessOutput(
                executable: curl,
                arguments: [
                    "-sS",
                    "-o", "/dev/null",
                    "-w", "%{http_code}",
                    "-X", "POST",
                    "http://\(host):\(port)/api/mcp/servers/\(encodedServerID)/connect",
                    "-H", "Authorization: Bearer \(token)",
                ],
                currentDirectory: Self.projectRoot
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
            if connectOutput == "200" || connectOutput == "201" {
                registered.insert(spec.serverID)
            }
        }
        return registered
    }

    func mcpServerToolCount(_ spec: DetourMCPServerSpec) -> Int? {
        guard let token = swooshAPIToken(),
              let curl = executable(named: "curl") ?? executableAtPath("/usr/bin/curl"),
              let encodedServerID = spec.serverID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        let port = ProcessInfo.processInfo.environment["SWOOSH_PORT"]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "8787"
        guard let output = runProcessOutput(
            executable: curl,
            arguments: [
                "-sS",
                "http://127.0.0.1:\(port)/api/mcp/servers/\(encodedServerID)/tools",
                "-H", "Authorization: Bearer \(token)",
            ],
            currentDirectory: Self.projectRoot
        ),
              let data = output.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tools = object["tools"] as? [[String: Any]] else {
            return nil
        }
        return tools.count
    }

    func writeMCPCreateRequest(_ spec: DetourMCPServerSpec) throws -> URL {
        let directory = fileManager.homeDirectoryForCurrentUser
            .appending(path: ".detour")
            .appending(path: "mcp-setup")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let request = DetourMCPServerCreateRequest(
            id: spec.serverID,
            name: spec.displayName,
            description: spec.detail,
            transport: spec.transport,
            command: spec.transport == "stdio" ? spec.command : nil,
            arguments: spec.transport == "stdio" ? spec.arguments : nil,
            workingDirectory: spec.transport == "stdio" ? spec.workingDirectory : nil,
            environmentSecretRefs: spec.environmentSecretRefs.isEmpty ? nil : spec.environmentSecretRefs,
            baseURL: spec.baseURL,
            authorizationSecretRef: spec.authorizationSecretRef,
            localOnly: spec.localOnly,
            trustLevel: "userApproved",
            enabled: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(request)
        let url = directory.appending(path: "\(stableIDComponent(spec.serverID)).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    func swooshAPIToken() -> String? {
        let url = fileManager.homeDirectoryForCurrentUser
            .appending(path: ".swoosh")
            .appending(path: "api_token")
        guard let value = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    func executableAtPath(_ path: String) -> URL? {
        fileManager.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
    }

    func mcpServerProfile(
        _ spec: DetourMCPServerSpec,
        existing: DetourMCPServerProfile?
    ) -> DetourMCPServerProfile {
        DetourMCPServerProfile(
            id: spec.serverID,
            name: spec.displayName,
            description: spec.detail,
            transport: mcpTransportConfiguration(spec),
            state: "configured",
            trustLevel: "userApproved",
            enabled: true,
            toolPolicy: .safeDefault,
            resourcePolicy: .safeDefault,
            promptPolicy: .safeDefault,
            createdAt: existing?.createdAt ?? .now,
            updatedAt: .now
        )
    }

    func mcpTransportConfiguration(_ spec: DetourMCPServerSpec) -> DetourMCPTransportConfiguration {
        if spec.transport == "http", let baseURL = spec.baseURL {
            return .http(DetourMCPHTTPConfiguration(
                baseURL: baseURL,
                authorizationSecretRef: spec.authorizationSecretRef,
                localOnly: spec.localOnly ?? true
            ))
        }
        return .stdio(DetourMCPStdioConfiguration(
            command: spec.command ?? "",
            arguments: spec.arguments,
            workingDirectory: spec.workingDirectory,
            environmentSecretRefs: spec.environmentSecretRefs
        ))
    }

}
