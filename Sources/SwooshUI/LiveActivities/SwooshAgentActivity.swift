// SwooshUI/LiveActivities/SwooshAgentActivity.swift — Dynamic Island/Lock Screen (0.4A)
//
// Surfaces in-flight agent runs as a Live Activity on iOS — the Dynamic
// Island shows a compact orb + step counter; the Lock Screen shows the
// agent name, current step, and an Approve / Deny pair when waiting on the
// user. macOS targets compile this file out (Live Activities are iOS-only).
//
// The Widget Extension must register `SwooshAgentActivityWidget` in its
// bundle for the activity to surface. Hosts call `start(_:)` when an agent
// run begins and `update(_:)` as it progresses.

import Foundation
#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit
#endif

// MARK: - Attributes (static run identity)

#if os(iOS)
@available(iOS 16.1, *)
public struct SwooshAgentActivityAttributes: ActivityAttributes {
    public typealias ContentState = State

    public struct State: Codable, Hashable, Sendable {
        public var stepCount: Int
        public var currentStep: String
        public var status: AgentStatus
        public var pendingApprovalID: String?
        public var startedAt: Date

        public init(
            stepCount: Int = 0,
            currentStep: String = "Starting…",
            status: AgentStatus = .thinking,
            pendingApprovalID: String? = nil,
            startedAt: Date = Date()
        ) {
            self.stepCount = stepCount
            self.currentStep = currentStep
            self.status = status
            self.pendingApprovalID = pendingApprovalID
            self.startedAt = startedAt
        }
    }

    public enum AgentStatus: String, Codable, Hashable, Sendable {
        case thinking, acting, awaitingApproval, completed, error
    }

    public let agentName: String
    public let sessionID: String

    public init(agentName: String, sessionID: String) {
        self.agentName = agentName
        self.sessionID = sessionID
    }
}
#endif

// MARK: - Lifecycle helpers

#if os(iOS)
@available(iOS 16.1, *)
public enum SwooshAgentActivityCenter {

    /// Start a Live Activity for an agent run. Returns the activity ID for
    /// later updates. Throws if Live Activities are disabled by the user.
    @discardableResult
    public static func start(
        agentName: String,
        sessionID: String,
        initialState: SwooshAgentActivityAttributes.State = .init()
    ) throws -> String {
        let attributes = SwooshAgentActivityAttributes(
            agentName: agentName, sessionID: sessionID
        )
        let content = ActivityContent(
            state: initialState,
            staleDate: Date().addingTimeInterval(60 * 30)
        )
        let activity = try Activity.request(
            attributes: attributes,
            content: content
        )
        return activity.id
    }

    /// Push a new state to a running activity.
    public static func update(
        activityID: String,
        state: SwooshAgentActivityAttributes.State
    ) async {
        let activities = Activity<SwooshAgentActivityAttributes>.activities
        guard let activity = activities.first(where: { $0.id == activityID }) else { return }
        let content = ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(60 * 30)
        )
        await activity.update(content)
    }

    /// End a Live Activity. `dismissalPolicy` defaults to immediate.
    public static func end(activityID: String) async {
        let activities = Activity<SwooshAgentActivityAttributes>.activities
        guard let activity = activities.first(where: { $0.id == activityID }) else { return }
        await activity.end(dismissalPolicy: .immediate)
    }
}
#endif

// MARK: - Stub on non-iOS so call sites stay portable

#if !os(iOS)
public enum SwooshAgentActivityCenter {
    @discardableResult
    public static func start(
        agentName: String, sessionID: String
    ) throws -> String { "" }
    public static func update(activityID: String, state: Any) async {}
    public static func end(activityID: String) async {}
}
#endif
