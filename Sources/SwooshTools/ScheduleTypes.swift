// SwooshTools/ScheduleTypes.swift — Shared schedule value types
import Foundation

public struct SwooshSchedule: Codable, Sendable, Equatable {
    public let kind: SwooshScheduleKind
    public let expression: String
    public let display: String
    public let timezoneIdentifier: String

    public init(
        kind: SwooshScheduleKind,
        expression: String,
        display: String? = nil,
        timezoneIdentifier: String = TimeZone.current.identifier
    ) {
        self.kind = kind
        self.expression = expression
        self.display = display ?? expression
        self.timezoneIdentifier = timezoneIdentifier
    }
}

public enum SwooshScheduleKind: String, Codable, Sendable {
    case interval
    case daily
    case weekly
    case cron
    case once
}
