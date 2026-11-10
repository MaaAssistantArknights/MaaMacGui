import Foundation

/// Persisted daily wall-clock schedule. A revision validates an intent; it is
/// deliberately separate from the occurrence ID used for deduplication.
struct DailyTaskSchedule: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var hour: Int
    var minute: Int
    var isEnabled: Bool
    var forceStart: Bool = false

    var revision: String { "\(hour):\(minute):\(isEnabled):\(forceStart)" }
    var isValid: Bool { (0...23).contains(hour) && (0...59).contains(minute) }

    init(id: UUID, hour: Int, minute: Int, isEnabled: Bool, forceStart: Bool = false) {
        self.id = id
        self.hour = hour
        self.minute = minute
        self.isEnabled = isEnabled
        self.forceStart = forceStart
    }

    private enum CodingKeys: String, CodingKey { case id, hour, minute, isEnabled, forceStart }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        hour = try values.decode(Int.self, forKey: .hour)
        minute = try values.decode(Int.self, forKey: .minute)
        isEnabled = try values.decode(Bool.self, forKey: .isEnabled)
        forceStart = try values.decodeIfPresent(Bool.self, forKey: .forceStart) ?? false
    }
}

struct ScheduleOccurrence: Codable, Equatable, Identifiable, Sendable {
    enum Result: String, Codable, Sendable {
        case pending, started, completed, skipped, failed, cancelled, missed, interrupted
    }

    let id: String
    let planID: UUID
    let revision: String
    let scheduledAt: Date
    let expiresAt: Date
    var result: Result = .pending
    var detail = ""
    var runID: UUID?
    var updatedAt: Date
}

/// Uses strict matching and the first repeated wall-clock time. No 86,400-second
/// arithmetic: every day is obtained from the injected local Calendar.
enum ScheduleCalendar {
    static func occurrence(for plan: DailyTaskSchedule, on day: Date,
                           calendar: Calendar, grace: TimeInterval = 60) -> ScheduleOccurrence? {
        guard plan.isValid, let interval = calendar.dateInterval(of: .day, for: day) else { return nil }
        let date = calendar.dateComponents([.year, .month, .day], from: day)
        let localDay = String(format: "%04d-%02d-%02d", date.year ?? 0, date.month ?? 0, date.day ?? 0)
        let id = "\(plan.id.uuidString):\(localDay):\(plan.hour):\(plan.minute)"
        let matching = DateComponents(hour: plan.hour, minute: plan.minute, second: 0)
        let first = calendar.nextDate(after: interval.start.addingTimeInterval(-1), matching: matching,
                                      matchingPolicy: .strict, repeatedTimePolicy: .first, direction: .forward)
        if let first, first < interval.end {
            return ScheduleOccurrence(id: id, planID: plan.id, revision: plan.revision,
                                      scheduledAt: first, expiresAt: first.addingTimeInterval(grace), updatedAt: first)
        }
        // Missing DST time has no runnable instant. Keep a record for that day.
        return ScheduleOccurrence(id: id, planID: plan.id, revision: plan.revision,
                                  scheduledAt: interval.end, expiresAt: interval.end,
                                  result: .missed, detail: "nonexistentLocalTime", updatedAt: interval.end)
    }

    static func nextDate(for plan: DailyTaskSchedule, after now: Date, calendar: Calendar) -> Date? {
        guard plan.isValid else { return nil }
        return calendar.nextDate(after: now, matching: DateComponents(hour: plan.hour, minute: plan.minute, second: 0),
                                 matchingPolicy: .strict, repeatedTimePolicy: .first, direction: .forward)
    }
}
