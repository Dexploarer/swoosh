// SwooshFlow/WorkflowDraftGenerator.swift — /repeat draft generator (0.5A)
//
// Turns a session trace into a disabled, manual-only, reviewable workflow draft.
// Every unsafe tool is excluded or converted to humanReview.

import Foundation
import SwooshTools

// MARK: - Generator protocol

public protocol WorkflowDraftGenerating: Sendable {
    func generateDraft(
        from trace: SessionTrace,
        options: WorkflowDraftGenerationOptions
    ) async throws -> WorkflowDraft05A
}

// MARK: - Options

public struct WorkflowDraftGenerationOptions: Codable, Sendable {
    public let preferredName: String?
    public let includeWriteSteps: Bool
    public let includeHumanApprovalSteps: Bool
    public let manualOnly: Bool
    public let maxSteps: Int

    public init(
        preferredName: String? = nil,
        includeWriteSteps: Bool = false,
        includeHumanApprovalSteps: Bool = true,
        manualOnly: Bool = true,
        maxSteps: Int = 12
    ) {
        self.preferredName = preferredName
        self.includeWriteSteps = includeWriteSteps
        self.includeHumanApprovalSteps = includeHumanApprovalSteps
        self.manualOnly = manualOnly
        self.maxSteps = maxSteps
    }
}

// MARK: - Default generator

public struct DefaultWorkflowDraftGenerator: WorkflowDraftGenerating, Sendable {

    /// Tools that must NEVER become executable steps.
    private static let neverExecutableTools: Set<String> = [
        // Blockchain signing/broadcast
        "evm.tx_request_signature", "evm.tx_broadcast_signed",
        "solana.tx_request_signature", "solana.tx_send_signed",
        // Git push/file delete
        "git.push", "file.delete",
        // Wallet connect (requires human)
        "evm.wallet_connect", "solana.wallet_connect",
    ]

    /// Tools considered write/destructive.
    private static let writeTools: Set<String> = [
        "file.write", "file.patch",
        "git.commit", "git.apply_patch", "git.checkout",
    ]

    public init() {}

    public func generateDraft(
        from trace: SessionTrace,
        options: WorkflowDraftGenerationOptions
    ) async throws -> WorkflowDraft05A {
        // 1. Infer name
        let name = options.preferredName ?? inferName(from: trace)

        // 2. Convert tool traces to steps
        var steps: [WorkflowStep05A] = []
        var allPermissions: [SwooshPermission] = []
        var variables: [WorkflowVariable] = []
        var seenRootIDs: Set<String> = []

        for toolTrace in trace.toolCalls.prefix(options.maxSteps) {
            let toolName = toolTrace.toolName

            // Skip never-executable tools entirely
            if Self.neverExecutableTools.contains(toolName) {
                if options.includeHumanApprovalSteps {
                    steps.append(WorkflowStep05A(
                        index: steps.count + 1,
                        title: "⚠️ \(toolTrace.toolName) (excluded — requires human)",
                        kind: .humanReview,
                        toolName: toolName,
                        risk: .critical,
                        approval: .humanOnly,
                        sourceTraceID: toolTrace.id
                    ))
                }
                continue
            }

            // Handle write tools
            if Self.writeTools.contains(toolName) && !options.includeWriteSteps {
                if options.includeHumanApprovalSteps {
                    steps.append(WorkflowStep05A(
                        index: steps.count + 1,
                        title: "Review: \(toolTrace.toolName) (write step excluded by default)",
                        kind: .humanReview,
                        toolName: toolName,
                        risk: toolTrace.risk,
                        approval: .askEveryTime,
                        sourceTraceID: toolTrace.id
                    ))
                }
                continue
            }

            // Detect root ID variables
            let args = toolTrace.inputPreview
            if !args.isEmpty {
                if args.contains("rootBookmarkID") || args.contains("rootID") {
                    if seenRootIDs.isEmpty {
                        variables.append(WorkflowVariable(
                            name: "projectRoot",
                            type: .approvedRootID,
                            description: "Project root for file/git/swift operations"
                        ))
                    }
                    seenRootIDs.insert("projectRoot")
                }
            }

            // Build step
            let argsTemplate = templatizeArguments(toolTrace.inputPreview, variables: seenRootIDs)
            let stepKind: WorkflowStepKind = Self.writeTools.contains(toolName) ? .approvalGate : .toolCall

            steps.append(WorkflowStep05A(
                index: steps.count + 1,
                title: inferStepTitle(toolName: toolName),
                kind: stepKind,
                toolName: toolName,
                argumentsTemplate: argsTemplate,
                requiredPermissions: [toolTrace.permission],
                risk: toolTrace.risk,
                approval: toolTrace.approvalPolicy,
                sourceTraceID: toolTrace.id
            ))

            allPermissions.append(toolTrace.permission)
        }

        // 3. Add model summarize step if the last message was a summary
        if let lastAssistant = trace.assistantMessages.last,
           lastAssistant.content.count > 100 {
            steps.append(WorkflowStep05A(
                index: steps.count + 1,
                title: "Summarize results",
                kind: .modelSummarize,
                risk: .readOnly,
                approval: .never
            ))
        }

        // 4. Deduplicate permissions
        let uniquePerms = Array(Set(allPermissions))
        let permRequirements = uniquePerms.map { perm in
            WorkflowPermissionRequirement(
                permission: perm,
                reason: "Required by workflow steps",
                requiredForStepIDs: steps.filter { $0.requiredPermissions.contains(perm) }.map(\.id)
            )
        }

        // 5. Compute risk
        let risk = WorkflowRisk.compute(from: steps)

        // 6. Build provenance
        let provenance = WorkflowProvenance(
            sourceSessionID: trace.sessionID,
            sourceMessageIDs: trace.userMessages.map(\.id),
            sourceToolTraceIDs: trace.toolCalls.map(\.id),
            sourceApprovedMemoryIDs: trace.memoryIDsUsed
        )

        // 7. Build draft
        return WorkflowDraft05A(
            name: name,
            summary: inferSummary(from: trace, steps: steps),
            status: .draft,
            trigger: .manual,
            variables: variables,
            steps: steps,
            requiredPermissions: permRequirements,
            risk: risk,
            provenance: provenance
        )
    }

    // MARK: - Helpers

    private func inferName(from trace: SessionTrace) -> String {
        guard let firstUser = trace.userMessages.first else { return "Untitled Workflow" }
        let words = firstUser.content.prefix(80).components(separatedBy: .whitespaces)
        if words.count <= 6 { return firstUser.content.prefix(80).description }
        return words.prefix(6).joined(separator: " ") + "…"
    }

    private func inferSummary(from trace: SessionTrace, steps: [WorkflowStep05A]) -> String {
        let toolNames = steps.compactMap(\.toolName).map { $0.replacingOccurrences(of: ".", with: " ") }
        if toolNames.isEmpty { return "Workflow with \(steps.count) steps" }
        return "Run: \(toolNames.joined(separator: ", "))"
    }

    private func inferStepTitle(toolName: String) -> String {
        let parts = toolName.components(separatedBy: ".")
        let action = parts.last ?? toolName
        let domain = parts.first ?? ""
        return "\(domain.capitalized): \(action.replacingOccurrences(of: "_", with: " "))"
    }

    private func templatizeArguments(_ preview: String?, variables: Set<String>) -> JSONValue? {
        guard let preview = preview else { return nil }
        // Replace concrete root IDs with {{projectRoot}} variable
        var templated = preview
        if variables.contains("projectRoot") {
            // Replace rootBookmarkID/rootID values with template syntax
            let patterns = [
                #"\"rootBookmarkID\"\s*:\s*\"[^\"]+\""#,
                #"\"rootID\"\s*:\s*\"[^\"]+\""#,
            ]
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern) {
                    let range = NSRange(templated.startIndex..., in: templated)
                    if regex.firstMatch(in: templated, range: range) != nil,
                       let key = templated.range(of: "rootBookmarkID") ?? templated.range(of: "rootID") {
                        let keyName = String(templated[key])
                        templated = regex.stringByReplacingMatches(
                            in: templated, range: range,
                            withTemplate: "\"\(keyName)\": \"{{projectRoot}}\""
                        )
                    }
                }
            }
        }
        return .string(templated)
    }
}
