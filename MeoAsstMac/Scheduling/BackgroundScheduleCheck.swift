import Foundation

/// A single, bounded launchd check. This process never runs Core or game tools.
struct BackgroundScheduleCheck {
    let files: BackgroundScheduleFiles
    let ledger: ScheduleOccurrenceStore

    @discardableResult
    func perform(now: Date, calendar: Calendar) throws -> Bool {
        try performIntent(now: now, calendar: calendar) != nil
    }

    func performIntent(now: Date, calendar: Calendar) throws -> BackgroundScheduleIntent? {
        let publication = try files.publication()
        guard publication.enabled else { return nil }
        guard let first = try Self.claimDue(plans: publication.plans, now: now, calendar: calendar,
                                           grace: 300, ledger: ledger, source: "backgroundIntent") else { return nil }
        let intent = BackgroundScheduleIntent(occurrence: first.1, profileID: publication.profileID)
        do {
            try files.deliver(intent)
            return intent
        } catch {
            try ledger.rejectBackgroundIntent(first.1.id, result: .failed, detail: "intentWriteFailed", now: now)
            throw error
        }
    }

    func recordWakeFailure(_ intent: BackgroundScheduleIntent, now: Date = .now) throws {
        try ledger.rejectBackgroundIntent(intent.occurrence.id, result: .failed, detail: "wakeFailed", now: now)
        try files.preserveFailedIntent(intent)
    }

    /// Both GUI and agent use this exact candidate window and stable winner.
    /// Selecting before claiming means a second trigger source cannot promote
    /// another plan when the winner was already accepted by the first source.
    static func claimDue(plans: [DailyTaskSchedule], now: Date, calendar: Calendar,
                         grace: TimeInterval, ledger: ScheduleOccurrenceStore,
                         source: String) throws -> (DailyTaskSchedule, ScheduleOccurrence)? {
        let today = calendar.startOfDay(for: now)
        var days = [today]
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today) { days.insert(yesterday, at: 0) }
        var runnable: [(DailyTaskSchedule, ScheduleOccurrence)] = []
        for day in days {
            for plan in plans.filter({ $0.isEnabled && $0.isValid }) {
                guard var occurrence = ScheduleCalendar.occurrence(for: plan, on: day, calendar: calendar, grace: grace) else { continue }
                let components = calendar.dateComponents([.hour, .minute], from: now)
                let missingTimeDue = occurrence.result == .missed && (day < today ||
                    (components.hour ?? 0) * 60 + (components.minute ?? 0) >= plan.hour * 60 + plan.minute)
                guard occurrence.scheduledAt <= now || missingTimeDue else { continue }
                let expired = grace <= 60 ? now >= occurrence.expiresAt : now > occurrence.expiresAt
                if occurrence.result == .missed || expired {
                    occurrence.result = .missed
                    occurrence.detail = occurrence.detail.isEmpty ? "triggerExpired" : occurrence.detail
                    _ = try ledger.claim(occurrence)
                } else {
                    occurrence.detail = source
                    runnable.append((plan, occurrence))
                }
            }
        }
        runnable.sort { left, right in
            left.1.scheduledAt == right.1.scheduledAt ? left.0.id.uuidString < right.0.id.uuidString : left.1.scheduledAt < right.1.scheduledAt
        }
        let batches = Dictionary(grouping: runnable, by: { $0.1.scheduledAt })
        let ordered = batches.keys.sorted().compactMap { batches[$0]?.map { $0.1 } }
        guard let claimed = try ledger.claimDueGroups(ordered),
              let plan = plans.first(where: { $0.id == claimed.planID }) else { return nil }
        return (plan, claimed)

    }
}
