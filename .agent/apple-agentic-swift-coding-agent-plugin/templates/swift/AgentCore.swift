import Foundation

public enum AgentToolAccess: Sendable {
    case readOnly
    case localMutationRequiresUserAction
    case permissionGated(String)
    case network(host: String)
    case destructiveRequiresConfirmation
}

public struct AgentToolDescriptor: Sendable, Codable, Hashable {
    public var name: String
    public var purpose: String
    public var access: String
    public var timeoutSeconds: Double

    public init(name: String, purpose: String, access: String, timeoutSeconds: Double = 15) {
        self.name = name
        self.purpose = purpose
        self.access = access
        self.timeoutSeconds = timeoutSeconds
    }
}

public struct AgentRunContext: Sendable {
    public var userInitiated: Bool
    public var localeIdentifier: String
    public var allowsNetwork: Bool
    public var allowsSensitiveData: Bool

    public init(userInitiated: Bool, localeIdentifier: String, allowsNetwork: Bool, allowsSensitiveData: Bool) {
        self.userInitiated = userInitiated
        self.localeIdentifier = localeIdentifier
        self.allowsNetwork = allowsNetwork
        self.allowsSensitiveData = allowsSensitiveData
    }
}

public actor AgentBudget {
    private var remainingToolCalls: Int

    public init(maxToolCalls: Int) {
        self.remainingToolCalls = maxToolCalls
    }

    public func consumeToolCall() throws {
        guard remainingToolCalls > 0 else { throw AgentError.toolBudgetExceeded }
        remainingToolCalls -= 1
    }
}

public enum AgentError: Error, Sendable, Equatable {
    case modelUnavailable
    case permissionDenied
    case toolBudgetExceeded
    case timeout
    case cancelled
    case invalidOutput
}
