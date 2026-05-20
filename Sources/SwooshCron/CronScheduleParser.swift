// SwooshCron/CronScheduleParser.swift — Natural schedule parsing
import Foundation

public enum CronScheduleParser {
    public static func parse(_ raw: String, now: Date = Date()) throws -> CronSchedule {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.split(separator: " ").count == 5 {
            return CronSchedule(kind: .cron, expression: text, display: raw)
        }
        if text.hasPrefix("every ") {
            let value = String(text.dropFirst("every ".count)).trimmingCharacters(in: .whitespaces)
            if let seconds = parseDuration(value) {
                return CronSchedule(kind: .interval, expression: "\(seconds)", display: raw)
            }
            if value.hasPrefix("day") {
                return CronSchedule(kind: .daily, expression: "09:00", display: raw)
            }
        }
        if text.hasPrefix("in "), let seconds = parseDuration(String(text.dropFirst(3))) {
            return CronSchedule(kind: .once, expression: ISO8601DateFormatter().string(from: now.addingTimeInterval(TimeInterval(seconds))), display: raw)
        }
        if text.hasPrefix("daily") || text.hasPrefix("every day") {
            return CronSchedule(kind: .daily, expression: parseClockTime(text) ?? "09:00", display: raw)
        }
        if text.hasPrefix("weekly") || text.contains("every monday") || text.contains("every tuesday") ||
            text.contains("every wednesday") || text.contains("every thursday") || text.contains("every friday") ||
            text.contains("every saturday") || text.contains("every sunday") {
            let weekday = parseWeekday(text) ?? 2
            let time = parseClockTime(text) ?? "09:00"
            return CronSchedule(kind: .weekly, expression: "\(weekday) \(time)", display: raw)
        }
        throw CronScheduleError.unsupported(raw)
    }

    public static func nextRun(after date: Date, schedule: CronSchedule) -> Date? {
        switch schedule.kind {
        case .interval:
            guard let seconds = Int(schedule.expression), seconds > 0 else { return nil }
            return date.addingTimeInterval(TimeInterval(seconds))
        case .once:
            return ISO8601DateFormatter().date(from: schedule.expression)
        case .daily:
            return nextDaily(after: date, clock: schedule.expression, timezone: schedule.timezoneIdentifier)
        case .weekly:
            let pieces = schedule.expression.split(separator: " ").map(String.init)
            guard pieces.count == 2, let weekday = Int(pieces[0]) else { return nil }
            return nextWeekly(after: date, weekday: weekday, clock: pieces[1], timezone: schedule.timezoneIdentifier)
        case .cron:
            return nextCron(after: date, expression: schedule.expression, timezone: schedule.timezoneIdentifier)
        }
    }

    private static func parseDuration(_ text: String) -> Int? {
        let compact = text.replacingOccurrences(of: " ", with: "")
        let number = Int(compact.prefix { $0.isNumber })
        guard let number else { return nil }
        if compact.contains("sec") || compact.hasSuffix("s") { return number }
        if compact.contains("min") || compact.hasSuffix("m") { return number * 60 }
        if compact.contains("hour") || compact.hasSuffix("h") { return number * 3600 }
        if compact.contains("day") || compact.hasSuffix("d") { return number * 86400 }
        return nil
    }

    private static func parseClockTime(_ text: String) -> String? {
        let regex = try? NSRegularExpression(pattern: #"(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#)
        let ns = NSRange(text.startIndex..., in: text)
        guard let match = regex?.matches(in: text, range: ns).last else { return nil }
        func group(_ index: Int) -> String? {
            guard match.range(at: index).location != NSNotFound, let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
        guard var hour = group(1).flatMap(Int.init) else { return nil }
        let minute = group(2).flatMap(Int.init) ?? 0
        if group(3) == "pm", hour < 12 { hour += 12 }
        if group(3) == "am", hour == 12 { hour = 0 }
        guard (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return String(format: "%02d:%02d", hour, minute)
    }

    private static func parseWeekday(_ text: String) -> Int? {
        let days = ["sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7]
        return days.first { text.contains($0.key) }?.value
    }

    private static func nextDaily(after date: Date, clock: String, timezone: String) -> Date? {
        guard let hm = parseHM(clock) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezone) ?? .current
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = hm.hour
        components.minute = hm.minute
        components.second = 0
        guard let candidate = calendar.date(from: components) else { return nil }
        return candidate > date ? candidate : calendar.date(byAdding: .day, value: 1, to: candidate)
    }

    private static func nextWeekly(after date: Date, weekday: Int, clock: String, timezone: String) -> Date? {
        guard let hm = parseHM(clock) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezone) ?? .current
        var components = DateComponents()
        components.weekday = weekday
        components.hour = hm.hour
        components.minute = hm.minute
        components.second = 0
        return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTimePreservingSmallerComponents)
    }

    private static func nextCron(after date: Date, expression: String, timezone: String) -> Date? {
        let fields = expression.split(separator: " ").map(String.init)
        guard fields.count == 5 else { return nil }
        var probe = date.addingTimeInterval(60)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezone) ?? .current
        for _ in 0..<(366 * 24 * 60) {
            let c = calendar.dateComponents([.minute, .hour, .day, .month, .weekday], from: probe)
            if field(fields[0], matches: c.minute) &&
                field(fields[1], matches: c.hour) &&
                field(fields[2], matches: c.day) &&
                field(fields[3], matches: c.month) &&
                field(fields[4], matches: c.weekday) {
                return probe
            }
            probe = probe.addingTimeInterval(60)
        }
        return nil
    }

    private static func field(_ field: String, matches value: Int?) -> Bool {
        guard let value else { return false }
        if field == "*" { return true }
        return Int(field) == value
    }

    private static func parseHM(_ value: String) -> (hour: Int, minute: Int)? {
        let pieces = value.split(separator: ":").map(String.init)
        guard pieces.count == 2, let hour = Int(pieces[0]), let minute = Int(pieces[1]) else { return nil }
        return (hour, minute)
    }
}

public enum CronScheduleError: Error, Sendable, LocalizedError {
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .unsupported(let value): "unsupported schedule: \(value)"
        }
    }
}
