// DetourCanvasWorkspaceBuilder.swift — deterministic canvas node builder (0.5A)

import Foundation

@MainActor
enum DetourCanvasWorkspaceBuilder {
    static func build(
        kind: DetourCanvasKind,
        request: String,
        sections: [DetourSetupInsightSection],
        summary: DetourSetupCapabilitySummary,
        wallet: DetourHomeWalletModel,
        inbox: DetourHomeInboxModel
    ) -> DetourCanvasWorkspace {
        let nodes = canvasNodes(kind: kind, sections: sections, summary: summary, wallet: wallet, inbox: inbox)
        let artifacts = canvasArtifacts(kind: kind, request: request, sections: sections, summary: summary, wallet: wallet, inbox: inbox)
        return DetourCanvasWorkspace(
            title: "\(kind.title) canvas",
            subtitle: subtitle(kind: kind, summary: summary, wallet: wallet, inbox: inbox),
            request: request.trimmingCharacters(in: .whitespacesAndNewlines),
            nodes: nodes,
            edges: edges(for: nodes),
            artifacts: artifacts
        )
    }

    private static func canvasNodes(
        kind: DetourCanvasKind,
        sections: [DetourSetupInsightSection],
        summary: DetourSetupCapabilitySummary,
        wallet: DetourHomeWalletModel,
        inbox: DetourHomeInboxModel
    ) -> [DetourCanvasNode] {
        switch kind {
        case .media:
            return mediaNodes(summary: summary)
        case .workflow:
            return workflowNodes(summary: summary, inbox: inbox)
        case .prompt:
            return promptNodes(sections: sections)
        case .models:
            return modelNodes(sections: sections)
        case .knowledge:
            return knowledgeNodes(sections: sections)
        case .portfolio:
            return portfolioNodes(wallet: wallet, sections: sections)
        }
    }

    private static func mediaNodes(summary: DetourSetupCapabilitySummary) -> [DetourCanvasNode] {
        [
            node("brief", "Creative brief", "Voice or text direction for the scene.", "text.alignleft", .blue, .ready),
            node("comfy", "ComfyUI graph", "Image, video, or asset generation workflow.", "square.stack.3d.up", .indigo, .needsSetup),
            node("models", "Model choices", "Local and remote generation providers.", "cpu", .green, providerStatus(summary)),
            node("review", "Human review", "Approve files before they are saved or posted.", "checkmark.shield", .orange, .pending),
            node("output", "Generated assets", "Images, clips, thumbnails, and variants.", "photo.on.rectangle", .blue, .pending),
        ]
    }

    private static func workflowNodes(summary: DetourSetupCapabilitySummary, inbox: DetourHomeInboxModel) -> [DetourCanvasNode] {
        [
            node("trigger", "Trigger", "Voice, schedule, message, or manual start.", "bolt", .blue, .ready),
            node("planner", "Planner", "Turns the request into steps and gates.", "list.bullet.rectangle", .green, .ready),
            node("tools", "Tools", "\(summary.using) selected tools and connectors.", "wrench.and.screwdriver", .green, .ready),
            node("approval", "Approvals", "\(inbox.pendingCount) pending user decisions.", "checkmark.shield", .orange, inbox.pendingCount > 0 ? .pending : .ready),
            node("ledger", "Run history", "Auditable output, logs, and replay state.", "clock.arrow.circlepath", .indigo, .ready),
        ]
    }

    private static func promptNodes(sections: [DetourSetupInsightSection]) -> [DetourCanvasNode] {
        let relationshipCount = count(in: sections, category: .relationships)
        return [
            node("voice", "Voice rules", "How Detour speaks as itself or as you.", "person.wave.2", .blue, .ready),
            node("examples", "Examples", "Preferred replies, non-replies, and edge cases.", "quote.bubble", .green, .pending),
            node("relationships", "Relationships", "\(relationshipCount) people available for guidance.", "person.2", .indigo, relationshipCount > 0 ? .ready : .needsSetup),
            node("templates", "Templates", "Prompt and message templates guarded by setup state.", "doc.richtext", .green, .ready),
            node("tests", "Checks", "Validate behavior before automation is trusted.", "checklist", .orange, .pending),
        ]
    }

    private static func modelNodes(sections: [DetourSetupInsightSection]) -> [DetourCanvasNode] {
        let providers = count(in: sections, category: .providers)
        return [
            node("router", "Provider router", "\(providers) provider candidates.", "arrow.triangle.branch", .blue, providers > 0 ? .ready : .needsSetup),
            node("local", "Local models", "MLX and local runtimes when installed.", "desktopcomputer", .green, .pending),
            node("remote", "Remote models", "OpenAI, Claude, Gemini, OpenRouter, and compatible APIs.", "network", .indigo, .ready),
            node("rag", "RAG path", "Embeddings, retrieval, and approved memories.", "books.vertical", .orange, .pending),
            node("fallback", "Fallback policy", "How Detour rotates if a model fails.", "arrow.clockwise", .blue, .pending),
        ]
    }

    private static func knowledgeNodes(sections: [DetourSetupInsightSection]) -> [DetourCanvasNode] {
        let signals = count(in: sections, category: .appActivitySignals)
        return [
            node("sources", "Sources", "\(signals) local usage signals summarized.", "tray.and.arrow.down", .blue, signals > 0 ? .ready : .pending),
            node("redaction", "Redaction", "Secrets and raw history stay out of prompts.", "eye.slash", .green, .ready),
            node("index", "Index", "Files, memories, and relationship context.", "square.grid.3x3", .indigo, .pending),
            node("retrieval", "Retrieval", "Only approved context reaches the agent.", "magnifyingglass", .green, .ready),
            node("review", "Memory review", "User approval before lasting memory.", "checkmark.shield", .orange, .pending),
        ]
    }

    private static func portfolioNodes(wallet: DetourHomeWalletModel, sections: [DetourSetupInsightSection]) -> [DetourCanvasNode] {
        let connectors = count(in: sections, category: .connectors)
        let walletStatus: DetourCanvasStatus = wallet.dashboard == nil ? .offline : .live
        return [
            node("wallets", "Wallets", wallet.dashboard.map { "\($0.assets.count) tracked entries." } ?? "Wallet dashboard offline.", "wallet.pass", .blue, walletStatus),
            node("solana", "Solana", "Read, swap, and launchpad context.", "sparkles", .green, walletStatus == .live ? .ready : .pending),
            node("evm", "BNB and EVM", "BNB Chain, Base, Ethereum, and DEX routing.", "hexagon", .orange, walletStatus == .live ? .ready : .pending),
            node("hyperliquid", "Hyperliquid", "Market data and guarded trading path.", "chart.line.uptrend.xyaxis", .indigo, walletStatus == .live ? .ready : .pending),
            node("social", "Social context", "\(connectors) connector candidates for alerts and replies.", "bubble.left.and.bubble.right", .blue, connectors > 0 ? .ready : .needsSetup),
        ]
    }

    private static func subtitle(
        kind: DetourCanvasKind,
        summary: DetourSetupCapabilitySummary,
        wallet: DetourHomeWalletModel,
        inbox: DetourHomeInboxModel
    ) -> String {
        switch kind {
        case .portfolio where wallet.dashboard == nil:
            return "Connect wallet status to make this canvas live."
        case .workflow where inbox.pendingCount > 0:
            return "\(inbox.pendingCount) pending approval items can be wired into this workflow."
        default:
            return "\(summary.using) selected setup items can feed this canvas."
        }
    }

    private static func providerStatus(_ summary: DetourSetupCapabilitySummary) -> DetourCanvasStatus {
        summary.using > 0 ? .ready : .needsSetup
    }

    private static func canvasArtifacts(
        kind: DetourCanvasKind,
        request: String,
        sections: [DetourSetupInsightSection],
        summary: DetourSetupCapabilitySummary,
        wallet: DetourHomeWalletModel,
        inbox: DetourHomeInboxModel
    ) -> [DetourCanvasArtifact] {
        let cleanedRequest = request.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestLine = cleanedRequest.isEmpty ? "Open a \(kind.title.lowercased()) workspace." : cleanedRequest
        let counts = "- Setup selected: \(summary.using)\n- Needs attention: \(summary.needsAttention)\n- Pending approvals: \(inbox.pendingCount)"
        switch kind {
        case .media:
            return [
                artifact("media-brief", "Generation brief", "Voice to graph handoff", .brief, .ready, """
                # Media canvas
                \(requestLine)

                ## Inputs
                \(counts)

                ## Draft graph
                - Prompt
                - Style and reference set
                - Local or remote model
                - Review gate
                - Export target
                """),
                artifact("media-runbook", "Run plan", "Safe asset generation steps", .runbook, .pending, """
                # Run plan
                - [ ] Confirm prompt and output type
                - [ ] Choose generation provider
                - [ ] Generate preview
                - [ ] Ask before saving or posting
                """),
            ]
        case .workflow:
            return [
                artifact("workflow-spec", "Workflow spec", "Trigger, tools, approvals, replay", .workspace, .ready, """
                # Workflow canvas
                \(requestLine)

                ## Flow
                - Trigger
                - Planner
                - Tool calls
                - Approval gates
                - Audit log
                - Replay
                """),
                artifact("workflow-checks", "Checks", "What must pass before automation", .runbook, .pending, """
                # Verification
                - [ ] Connector whoami passes
                - [ ] Read/list call works
                - [ ] Risky writes require approval
                - [ ] Replay has enough context
                """),
            ]
        case .prompt:
            return [
                artifact("prompt-sheet", "Character sheet", "Voice and response rules", .template, .ready, """
                # Character sheet
                ## Voice
                - Direct
                - Useful
                - Context-aware

                ## Account behavior
                - As me: act from the user's voice and relationships
                - As agent: act from Detour's own identity
                - Shared: read both contexts, ask before writing
                """),
                artifact("prompt-tests", "Examples", "Reply and non-reply cases", .runbook, .pending, """
                # Behavior checks
                - [ ] Should reply
                - [ ] Should stay quiet
                - [ ] Should ask first
                - [ ] Should escalate immediately
                """),
            ]
        case .models:
            let providers = count(in: sections, category: .providers)
            return [
                artifact("model-routing", "Routing policy", "Provider fallback draft", .template, providers > 0 ? .ready : .needsSetup, """
                # Model routing
                ## Available candidates
                \(providers)

                ## Policy
                1. Prefer local when quality is enough.
                2. Use the configured default for general reasoning.
                3. Rotate only after a real failure.
                4. Keep provider errors visible.
                """),
                artifact("model-eval", "Eval loop", "Checks before making a model default", .runbook, .pending, """
                # Model checks
                - [ ] Basic chat
                - [ ] Tool-call formatting
                - [ ] Long-context answer
                - [ ] Cost and latency sample
                """),
            ]
        case .knowledge:
            return [
                artifact("knowledge-boundary", "Context boundary", "What can enter prompts", .brief, .ready, """
                # Knowledge canvas
                Approved memories and setup summaries can be used.

                ## Never shown here
                - Raw cookies
                - Raw browser history
                - Raw credentials
                - Rejected memories
                - Raw Scout records
                """),
                artifact("knowledge-index", "Index plan", "Memory and retrieval shape", .workspace, .pending, """
                # Retrieval plan
                - Sources
                - Redaction
                - Index
                - Retrieval
                - Human review
                """),
            ]
        case .portfolio:
            let walletState = wallet.dashboard == nil ? "Wallet status is offline." : "Wallet status is loaded."
            return [
                artifact("portfolio-brief", "Portfolio brief", "Wallet and social context", .brief, wallet.dashboard == nil ? .offline : .live, """
                # Portfolio canvas
                \(walletState)

                ## Networks
                - Solana
                - BNB Chain
                - EVM
                - Hyperliquid

                ## Social loop
                - Alerts
                - Draft replies
                - Approval before posting
                """),
                artifact("portfolio-watch", "Watchlist", "Signals Detour can watch", .runbook, .pending, """
                # Watchlist
                - [ ] Wallet movement
                - [ ] Mentions and DMs
                - [ ] Launchpad opportunities
                - [ ] Risk alerts
                """),
            ]
        }
    }

    private static func count(in sections: [DetourSetupInsightSection], category: DetourSetupInsightCategory) -> Int {
        sections.first { $0.id == category.rawValue }?.items.count ?? 0
    }

    private static func edges(for nodes: [DetourCanvasNode]) -> [DetourCanvasEdge] {
        zip(nodes, nodes.dropFirst()).map { DetourCanvasEdge(from: $0.id, to: $1.id) }
    }

    private static func node(
        _ id: String,
        _ title: String,
        _ subtitle: String,
        _ systemImage: String,
        _ tone: DetourGeneratedTone,
        _ status: DetourCanvasStatus
    ) -> DetourCanvasNode {
        DetourCanvasNode(id: id, title: title, subtitle: subtitle, systemImage: systemImage, tone: tone, status: status)
    }

    private static func artifact(
        _ id: String,
        _ title: String,
        _ subtitle: String,
        _ kind: DetourCanvasArtifactKind,
        _ status: DetourCanvasStatus,
        _ markdown: String
    ) -> DetourCanvasArtifact {
        DetourCanvasArtifact(id: id, title: title, subtitle: subtitle, kind: kind, status: status, markdown: markdown)
    }
}
