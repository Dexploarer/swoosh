// SwooshUI/Inspector/SwooshInspector.swift — Native side-panel detail (0.4A)
//
// A reusable Inspector pane that flips between three modes depending on
// what's selected in the dashboard:
//
//   - Audit log row → show the full `ResponseAuditRecord` (memories, model,
//     exclusions, timestamps)
//   - Pending approval → show the proposed tool call + arguments JSON
//   - Running agent → show the live event stream + current step
//
// Wire via `.inspector(isPresented:)` on the dashboard. Mode is determined
// from a single `SwooshInspectorTarget` value injected through environment.

import SwiftUI
import SwooshGenerativeUI

// MARK: - Target

/// What the inspector is currently focused on. The dashboard sets this when
/// the user selects a row in the audit log, approvals list, or agent list.
public enum SwooshInspectorTarget: Equatable, Sendable {
    case none
    case auditRecord(SwooshInspectorAudit)
    case approval(SwooshInspectorApproval)
    case agentRun(SwooshInspectorAgentRun)
}

// MARK: - Display models (UI-side; not the canonical audit shape)

public struct SwooshInspectorAudit: Equatable, Sendable, Identifiable {
    public let id: String
    public let sessionID: String
    public let responseID: String
    public let model: String
    public let memoryIDs: [String]
    public let setupReportUsed: Bool
    public let permissionSummaryUsed: Bool
    public let createdAt: Date

    public init(
        id: String, sessionID: String, responseID: String, model: String,
        memoryIDs: [String], setupReportUsed: Bool,
        permissionSummaryUsed: Bool, createdAt: Date
    ) {
        self.id = id
        self.sessionID = sessionID
        self.responseID = responseID
        self.model = model
        self.memoryIDs = memoryIDs
        self.setupReportUsed = setupReportUsed
        self.permissionSummaryUsed = permissionSummaryUsed
        self.createdAt = createdAt
    }
}

public struct SwooshInspectorApproval: Equatable, Sendable, Identifiable {
    public let id: String
    public let toolName: String
    public let permission: String
    public let risk: String
    public let argumentsJSON: String
    public let requestedAt: Date

    public init(
        id: String, toolName: String, permission: String, risk: String,
        argumentsJSON: String, requestedAt: Date
    ) {
        self.id = id
        self.toolName = toolName
        self.permission = permission
        self.risk = risk
        self.argumentsJSON = argumentsJSON
        self.requestedAt = requestedAt
    }
}

public struct SwooshInspectorAgentRun: Equatable, Sendable, Identifiable {
    public let id: String
    public let agentName: String
    public let sessionID: String
    public let currentStep: String
    public let stepCount: Int
    public let startedAt: Date

    public init(
        id: String, agentName: String, sessionID: String,
        currentStep: String, stepCount: Int, startedAt: Date
    ) {
        self.id = id
        self.agentName = agentName
        self.sessionID = sessionID
        self.currentStep = currentStep
        self.stepCount = stepCount
        self.startedAt = startedAt
    }
}

// MARK: - Inspector view

public struct SwooshInspectorView: View {
    public let target: SwooshInspectorTarget
    @Binding public var isPresented: Bool

    public init(target: SwooshInspectorTarget, isPresented: Binding<Bool>) {
        self.target = target
        self._isPresented = isPresented
    }

    public var body: some View {
        Group {
            switch target {
            case .none:
                emptyState
            case let .auditRecord(record):
                auditView(record)
            case let .approval(item):
                approvalView(item)
            case let .agentRun(run):
                agentRunView(run)
            }
        }
        .frame(minWidth: 280)
        .padding(20)
        .background(.regularMaterial)
    }

    // MARK: - Modes

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 36))
                .foregroundStyle(VoltPaper.mutedFg)
                .swooshBreathe()
            Text("Select a row to inspect")
                .font(.subheadline)
                .foregroundStyle(VoltPaper.mutedFg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func auditView(_ r: SwooshInspectorAudit) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                inspectorHeader(
                    title: "Response Audit",
                    subtitle: r.responseID,
                    systemImage: "list.bullet.rectangle.fill"
                )

                metaRow("Model", value: r.model, monospaced: true)
                metaRow("Session", value: r.sessionID, monospaced: true)
                metaRow("Recorded", value: r.createdAt.formatted(date: .abbreviated, time: .standard))

                if !r.memoryIDs.isEmpty {
                    Text("Memories used")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(VoltPaper.mutedFg)
                        .textCase(.uppercase)
                    ForEach(r.memoryIDs, id: \.self) { id in
                        HStack {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .foregroundStyle(.tint)
                            Text(id)
                                .font(.system(size: 11, design: .monospaced))
                        }
                    }
                }

                Divider().padding(.vertical, 4)

                Text("Context flags")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(VoltPaper.mutedFg)
                    .textCase(.uppercase)
                flagPill("Setup report",   on: r.setupReportUsed)
                flagPill("Permissions",    on: r.permissionSummaryUsed)
                flagPill("Excluded raw scout",  on: true)
                flagPill("Excluded rejected",   on: true)
                flagPill("Excluded cookies",    on: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func approvalView(_ a: SwooshInspectorApproval) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                inspectorHeader(
                    title: "Approval Required",
                    subtitle: a.toolName,
                    systemImage: "hand.raised.fill"
                )

                metaRow("Permission", value: a.permission, monospaced: true)
                metaRow("Risk", value: a.risk, monospaced: true)
                metaRow("Requested", value: a.requestedAt.formatted(date: .abbreviated, time: .standard))

                Text("Arguments")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(VoltPaper.mutedFg)
                    .textCase(.uppercase)
                Text(a.argumentsJSON)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(VoltPaper.mutedFg.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

                HStack {
                    Button(role: .destructive) {
                        NotificationCenter.default.post(name: .swooshDenyApproval, object: a.id)
                    } label: {
                        Label("Deny", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button {
                        NotificationCenter.default.post(name: .swooshApproveApproval, object: a.id)
                    } label: {
                        Label("Approve once", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func agentRunView(_ run: SwooshInspectorAgentRun) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                inspectorHeader(
                    title: run.agentName,
                    subtitle: run.sessionID,
                    systemImage: "cpu.fill"
                )

                metaRow("Started", value: run.startedAt.formatted(.relative(presentation: .named)))
                metaRow("Step", value: "\(run.stepCount)", monospaced: true)

                Text("Current step")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(VoltPaper.mutedFg)
                    .textCase(.uppercase)
                Text(run.currentStep)
                    .font(.system(size: 12))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))

                HStack {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(VoltPaper.accent)
                        .swooshPulse()
                    Text("Running")
                        .font(.caption)
                        .foregroundStyle(VoltPaper.mutedFg)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Builders

    private func inspectorHeader(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 18))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(VoltPaper.mutedFg)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
    }

    private func metaRow(_ key: String, value: String, monospaced: Bool = false) -> some View {
        HStack {
            Text(key)
                .font(.caption)
                .foregroundStyle(VoltPaper.mutedFg)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: monospaced ? .monospaced : .default))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    private func flagPill(_ label: String, on: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: on ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(on ? VoltPaper.accent : VoltPaper.mutedFg)
            Text(label)
                .font(.system(size: 12))
        }
    }
}

// MARK: - Notification names

public extension Notification.Name {
    static let swooshApproveApproval = Notification.Name("ai.swoosh.approveApproval")
    static let swooshDenyApproval    = Notification.Name("ai.swoosh.denyApproval")
}
