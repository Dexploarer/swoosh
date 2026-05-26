// DetourPersonalizationReview.swift — setup review section assembly helpers (0.5A)

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
    func calibrationQuestions(
        result: DetourPersonalizationScanResult,
        approvedCandidateIDs: Set<String>,
        setupCandidateScopes: [String: DetourDelegationRole],
        userName: String,
        agentName: String
    ) -> [String] {
        let selected = result.setupCandidates.filter { approvedCandidateIDs.contains($0.id) }
        let connectors = selected
            .filter { $0.category == .connector }
            .map(\.title)
            .sorted()
        let mcpServers = selected
            .filter { $0.category == .mcp }
            .map(\.title)
            .sorted()
        let models = selected
            .filter { $0.category == .model }
            .map(\.title)
            .sorted()
        let userOwned = selected
            .filter { (setupCandidateScopes[$0.id] ?? $0.scope) == .user }
            .map(\.title)
            .sorted()
        let agentOwned = selected
            .filter { (setupCandidateScopes[$0.id] ?? $0.scope) == .agent }
            .map(\.title)
            .sorted()
        let selectedRelationshipIDs = Set(result.relationshipCandidates.filter(\.selected).map(\.id))
        let relationshipMapApproved = approvedCandidateIDs.contains("context.relationships")
        let relationshipQuestions = result.relationshipCandidates
            .filter { relationshipMapApproved || selectedRelationshipIDs.contains($0.id) }
            .prefix(40)
        let displayUser = userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "you" : userName
        let displayAgent = agentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Detour" : agentName
        var questions = [
            "When \(displayAgent) is acting as \(displayUser), what should it never send, buy, post, delete, approve, or schedule without checking first?",
            "When \(displayAgent) is acting as itself, what voice, signature, and boundaries should it use?",
            "For your accounts\(userOwned.isEmpty ? "" : " (\(userOwned.joined(separator: ", ")))"), what messages should \(displayAgent) answer directly, what should it draft, and what should it bring to you first?",
            "For agent-owned accounts\(agentOwned.isEmpty ? "" : " (\(agentOwned.joined(separator: ", ")))"), what can \(displayAgent) do proactively without sounding like you?",
        ]
        questions.append(contentsOf: relationshipQuestions.map {
            relationshipQuestionPrompt(for: $0, userName: displayUser, agentName: displayAgent)
        })
        for connector in connectors {
            questions.append("On \(connector), give \(displayAgent) an example message it should answer and the kind of answer you want.")
            questions.append("On \(connector), give \(displayAgent) an example message it should not answer, plus what it should do instead.")
        }
        for server in mcpServers {
            questions.append("For \(server), which tools can \(displayAgent) use freely, which should always ask first, and what results should become memory?")
        }
        questions.append(contentsOf: [
            "What should \(displayAgent) notify you about immediately, batch into a daily brief, or keep quiet unless you ask?",
            "Which people, projects, repos, or conversations should always be high priority?",
            "What should \(displayAgent) remember after conversations, and what should it deliberately forget?",
            "When \(displayAgent) sees app activity, Git history, logs, connector health, or other machine events, what should become context for later?",
            "What should \(displayAgent) manifest in the background: goals, skills, hooks, schedules, cleanup, relationship follow-ups, or something else?",
            "Which hooks or automations should \(displayAgent) propose before running in each area of your life or work?",
            "Which model provider should be the default for quick replies, coding, private decisions, and long reasoning\(models.isEmpty ? "" : " from \(models.joined(separator: ", "))")?",
            "If a provider, credential, or connector fails, how should \(displayAgent) rotate, retry, or ask you before continuing?",
            "What examples should \(displayAgent) use to decide whether to reply, ignore, stop, or escalate a message?",
            "Anything else \(displayAgent) should know before it starts acting as your personal agent?"
        ])
        return questions
    }

    func relationshipQuestionPrompt(
        for relationship: DetourRelationshipCandidate,
        userName: String,
        agentName: String
    ) -> String {
        let activity = relationshipActivityDescription(relationship)
        return "Relationship: \(relationship.displayName) (\(activity)). Who is this person to \(userName), what tone and priority should \(agentName) use with them, what can \(agentName) handle directly, what should be drafted or escalated, and what boundaries or sensitive context should it remember?"
    }

    func relationshipActivityDescription(_ relationship: DetourRelationshipCandidate) -> String {
        var parts = [relationship.source]
        if let count = relationship.messageCount {
            parts.append("\(count) messages")
        }
        if let lastSeen = relationship.lastSeenDescription {
            parts.append("last seen \(lastSeen)")
        }
        return parts.joined(separator: ", ")
    }

    func relationshipGuidance(
        result: DetourPersonalizationScanResult,
        answers: [DetourPersonalizationCalibrationAnswer]
    ) -> [DetourRelationshipGuidance] {
        result.relationshipCandidates.compactMap { relationship in
            guard let answer = answers.first(where: { $0.question.hasPrefix("Relationship: \(relationship.displayName) (") }),
                  !answer.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return DetourRelationshipGuidance(
                relationshipID: relationship.id,
                displayName: relationship.displayName,
                source: relationship.source,
                tags: relationship.tags,
                messageCount: relationship.messageCount,
                lastSeenDescription: relationship.lastSeenDescription,
                guidance: answer.answer
            )
        }
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
        let questions = result.questions
        let records = answers.enumerated().map { index, answer in
            DetourPersonalizationCalibrationAnswer(
                id: "calibration.\(index + 1)",
                question: questions.indices.contains(index) ? questions[index] : "Additional context",
                answer: answer
            )
        }
        let selected = result.setupCandidates.filter { approvedCandidateIDs.contains($0.id) }
        let scopeMap = setupCandidateScopes.mapValues(\.rawValue)
        let relationshipGuidance = relationshipGuidance(result: result, answers: records)
        let eventRoutes = calibrationEventRoutes(selected: selected)
        let templates = calibrationTemplates(
            userName: userName,
            agentName: agentName,
            selected: selected,
            setupCandidateScopes: setupCandidateScopes,
            delegationProfiles: delegationProfiles,
            relationshipGuidance: relationshipGuidance,
            answers: records
        )
        let calibration = DetourPersonalizationCalibration(
            schemaVersion: 2,
            userName: userName,
            agentName: agentName,
            answers: records,
            selectedSetup: selected,
            setupCandidateScopes: scopeMap,
            delegationProfiles: delegationProfiles,
            relationshipGuidance: relationshipGuidance,
            eventRoutes: eventRoutes,
            templates: templates,
            savedAt: .now
        )
        try writeCalibration(calibration)
    }
}
