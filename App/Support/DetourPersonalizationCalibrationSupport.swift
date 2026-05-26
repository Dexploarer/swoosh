// DetourPersonalizationCalibrationSupport.swift — setup calibration question persistence (0.5A)

import AppKit
#if canImport(Contacts)
import Contacts
#endif
import Foundation
import OSLog
#if canImport(Security)
import Security
#endif

@MainActor
extension DetourPersonalizationRunner {
    func writeCalibration(_ calibration: DetourPersonalizationCalibration) throws {
        let detourDirectory = fileManager.homeDirectoryForCurrentUser.appending(path: ".detour")
        let swooshDirectory = fileManager.homeDirectoryForCurrentUser.appending(path: ".swoosh")
        let templateDirectory = swooshDirectory.appending(path: "templates")
        try fileManager.createDirectory(at: detourDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: swooshDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: templateDirectory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let calibrationData = try encoder.encode(calibration)
        try calibrationData.write(to: detourDirectory.appending(path: "personalization-calibration.json"), options: .atomic)
        try calibrationData.write(to: swooshDirectory.appending(path: "detour-calibration.json"), options: .atomic)

        let templateData = try encoder.encode(calibration.templates)
        try templateData.write(to: templateDirectory.appending(path: "detour-personalization.json"), options: .atomic)
    }

    func calibrationEventRoutes(
        selected: [DetourSetupCandidate]
    ) -> [DetourPersonalizationEventRoute] {
        var routes = [
            DetourPersonalizationEventRoute(
                event: "message:received",
                contextVariable: "{{recentMessages}}",
                templateTag: "recent_messages",
                policy: "Run shouldRespondTemplate before any reply."
            ),
            DetourPersonalizationEventRoute(
                event: "message:sent",
                contextVariable: "{{recentMessages}}",
                templateTag: "recent_messages",
                policy: "Use reflectionTemplate to extract approved learning candidates."
            ),
            DetourPersonalizationEventRoute(
                event: "action:completed",
                contextVariable: "{{detourEvents}}",
                templateTag: "machine_events",
                policy: "Summarize action results as context without exposing secrets."
            ),
            DetourPersonalizationEventRoute(
                event: "model:used",
                contextVariable: "{{providerHealth}}",
                templateTag: "provider_health",
                policy: "Track provider success, latency, and fallback choices."
            ),
            DetourPersonalizationEventRoute(
                event: "manifest:proposed",
                contextVariable: "{{manifestationCandidates}}",
                templateTag: "manifestation_candidates",
                policy: "Keep proposals pending until the user approves them."
            ),
        ]
        for connector in selected.filter({ $0.category == .connector }) {
            routes.append(DetourPersonalizationEventRoute(
                event: "\(connector.title.lowercased()):health",
                contextVariable: "{{connectorHealth}}",
                templateTag: "connector_health",
                policy: "Use connector health as machine context before routing messages."
            ))
        }
        return routes
    }

    func calibrationTemplates(
        userName: String,
        agentName: String,
        selected: [DetourSetupCandidate],
        setupCandidateScopes: [String: DetourDelegationRole],
        delegationProfiles: [DetourDelegationProfile],
        relationshipGuidance: [DetourRelationshipGuidance],
        answers: [DetourPersonalizationCalibrationAnswer]
    ) -> DetourPersonalizationTemplateSet {
        let context = calibrationContextBlock(
            userName: userName,
            agentName: agentName,
            selected: selected,
            setupCandidateScopes: setupCandidateScopes,
            delegationProfiles: delegationProfiles,
            relationshipGuidance: relationshipGuidance,
            answers: answers
        )
        let shouldRespond = """
        <task>Decide whether {{agentName}} should respond, ignore, stop, or escalate.</task>

        {{providers}}
        {{recentMessages}}
        {{detourEvents}}

        \(context)

        <rules>
        <rule>Respect whether the account is user-scoped or agent-scoped before choosing voice.</rule>
        <rule>Escalate when the calibrated examples say the user should decide.</rule>
        <rule>Never include raw credentials, cookies, browser history, or secret values in the response.</rule>
        </rules>

        <output>
        <response>
          <reasoning>Brief reason grounded in approved context.</reasoning>
          <action>RESPOND | IGNORE | ESCALATE | STOP</action>
        </response>
        </output>
        """
        let messageHandler = """
        <task>Write the response as {{agentName}} using the selected account perspective.</task>

        {{providers}}
        {{recentMessages}}
        {{detourEvents}}

        Available actions: {{actionNames}}

        \(context)

        <output>
        <response>
          <thought>Short routing and account-perspective note.</thought>
          <actions>ACTION_NAMES</actions>
          <providers>PROVIDER_NAMES</providers>
          <text>Response text.</text>
        </response>
        </output>
        """
        let reflection = """
        <task>Extract durable learning candidates after an interaction.</task>

        {{recentMessages}}
        {{detourEvents}}

        \(context)

        <output>
        {
          "thought": "What changed after this interaction",
          "facts": [
            {
              "claim": "Approved user preference or relationship fact",
              "type": "preference|relationship|workflow|boundary",
              "scope": "user|agent|shared"
            }
          ],
          "followUps": ["A user-visible follow-up to propose, not auto-run"]
        }
        </output>
        """
        let machineEvent = """
        <task>Convert machine-origin events, logs, health checks, and connector activity into compact context.</task>

        {{detourEvents}}
        {{connectorHealth}}
        {{providerHealth}}
        {{manifestationCandidates}}

        \(context)

        <output>
        <context_events>
          <event>
            <source>event source</source>
            <summary>Approved, non-secret context for the agent</summary>
            <route>message|provider|connector|manifestation|ignore</route>
          </event>
        </context_events>
        </output>
        """
        return DetourPersonalizationTemplateSet(
            shouldRespondTemplate: shouldRespond,
            messageHandlerTemplate: messageHandler,
            reflectionTemplate: reflection,
            machineEventTemplate: machineEvent
        )
    }

    func calibrationContextBlock(
        userName: String,
        agentName: String,
        selected: [DetourSetupCandidate],
        setupCandidateScopes: [String: DetourDelegationRole],
        delegationProfiles: [DetourDelegationProfile],
        relationshipGuidance: [DetourRelationshipGuidance],
        answers: [DetourPersonalizationCalibrationAnswer]
    ) -> String {
        let selectedAccounts = selected
            .map { candidate in
                let role = setupCandidateScopes[candidate.id] ?? candidate.scope
                let roleText = role?.rawValue ?? "shared"
                return "<account title=\"\(xmlEscaped(candidate.title))\" scope=\"\(roleText)\">\(xmlEscaped(candidate.detail))</account>"
            }
            .joined(separator: "\n")
        let profiles = delegationProfiles
            .map { profile in
                "<profile role=\"\(profile.role.rawValue)\" name=\"\(xmlEscaped(profile.displayName))\">\(xmlEscaped(profile.context))</profile>"
            }
            .joined(separator: "\n")
        let relationships = relationshipGuidance
            .map { guidance in
                let count = guidance.messageCount.map(String.init) ?? ""
                let lastSeen = guidance.lastSeenDescription ?? ""
                return """
                <relationship id="\(xmlEscaped(guidance.relationshipID))" name="\(xmlEscaped(guidance.displayName))" source="\(xmlEscaped(guidance.source))" messages="\(count)" last_seen="\(xmlEscaped(lastSeen))">
                  <tags>\(xmlEscaped(guidance.tags.joined(separator: ", ")))</tags>
                  <guidance>\(xmlEscaped(guidance.guidance))</guidance>
                </relationship>
                """
            }
            .joined(separator: "\n")
        let answerBlock = answers
            .map { answer in
                """
                <answer id="\(answer.id)">
                  <question>\(xmlEscaped(answer.question))</question>
                  <preference>\(xmlEscaped(answer.answer))</preference>
                </answer>
                """
            }
            .joined(separator: "\n")
        return """
        <detour_calibration>
        <identity>
          <user>\(xmlEscaped(userName))</user>
          <agent>\(xmlEscaped(agentName))</agent>
        </identity>
        <delegation_profiles>
        \(profiles)
        </delegation_profiles>
        <selected_setup>
        \(selectedAccounts)
        </selected_setup>
        <relationship_guidance>
        \(relationships)
        </relationship_guidance>
        <qa_preferences>
        \(answerBlock)
        </qa_preferences>
        </detour_calibration>
        """
    }

    func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    func setProgress(
        _ fraction: Double,
        _ title: String,
        _ onProgress: @escaping @MainActor (DetourPersonalizationProgress) -> Void,
        tick: Int = 0
    ) async {
        onProgress(
            DetourPersonalizationProgress(
                fraction: min(max(fraction, 0), 1),
                title: title,
                tip: tips[tick % tips.count]
            )
        )
    }

    var tips: [String] {
        [
            "Your context stays on this Mac.",
            "Scout turns patterns into reviewable memories.",
            "Installed apps shape plugin suggestions.",
            "Approve Keychain when macOS asks.",
            "Found credentials become yes or no approvals.",
            "Credential approvals can be user or agent scoped.",
            "Schedules can be changed later."
        ]
    }

    static var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
