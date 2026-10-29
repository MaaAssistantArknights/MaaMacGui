import Foundation

@main struct ScheduleTests {
    static var assertions = 0
    static func check(_ value: Bool, _ message: String) {
        assertions += 1
        if !value { fatalError(message) }
    }
    static func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    @MainActor static func main() async throws {
        if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--claim" {
            let store = ScheduleOccurrenceStore(directory: URL(fileURLWithPath: CommandLine.arguments[2]))
            let occurrence = ScheduleOccurrence(id: "shared", planID: UUID(uuidString: CommandLine.arguments[3])!, revision: "v1", scheduledAt: .now, expiresAt: .now.addingTimeInterval(300), updatedAt: .now)
            print(try store.claim(occurrence) ? "claimed" : "duplicate")
            return
        }
        let id = UUID()
        let legacy = Data("{\"id\":\"\(id)\",\"hour\":9,\"minute\":0,\"isEnabled\":true}".utf8)
        var plan = try JSONDecoder().decode(DailyTaskSchedule.self, from: legacy)
        check(!plan.forceStart, "legacy defaults false")
        plan.forceStart = true
        let roundTrip = try JSONDecoder().decode(DailyTaskSchedule.self, from: JSONEncoder().encode(plan))
        check(roundTrip == plan, "roundtrip")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        plan.hour = 2; plan.minute = 30
        let missing = ScheduleCalendar.occurrence(for: plan, on: date("2026-03-08T12:00:00Z"), calendar: cal)!
        check(missing.result == .missed, "spring missing time")
        plan.hour = 1
        let repeated = ScheduleCalendar.occurrence(for: plan, on: date("2026-11-01T12:00:00Z"), calendar: cal)!
        check(repeated.scheduledAt == date("2026-11-01T05:30:00Z"), "fall chooses first")
        let editedRevision = DailyTaskSchedule(id: id, hour: 1, minute: 30, isEnabled: true, forceStart: false)
        let edited = ScheduleCalendar.occurrence(for: editedRevision, on: date("2026-11-01T12:00:00Z"), calendar: cal)!
        check(edited.id == repeated.id, "revision not occurrence identity")
        check(edited.revision != repeated.revision, "revision changes")
        let next = ScheduleCalendar.nextDate(for: plan, after: date("2026-10-31T06:00:00Z"), calendar: cal)!
        check(next == date("2026-11-01T05:30:00Z"), "next first repeated time")
        plan.hour = -1
        check(ScheduleCalendar.nextDate(for: plan, after: .now, calendar: cal) == nil, "invalid hour")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ScheduleOccurrenceStore(directory: dir)
        check(try store.claim(repeated), "first claim")
        check(try !store.claim(repeated), "duplicate claim")
        try store.update(repeated.id, result: .started, runID: id)
        let records = try store.records()
        check(records.count == 1 && records[0].runID == id, "persisted claim")
        try store.recoverInterrupted()
        check(try store.records()[0].result == .interrupted, "crash does not replay")
        check(try !store.claim(repeated), "interrupted still claimed")
        var future = repeated
        let futurePlan = DailyTaskSchedule(id: repeated.planID, hour: 1, minute: 30, isEnabled: true)
        future = ScheduleCalendar.occurrence(for: futurePlan, on: date("2027-12-01T12:00:00Z"), calendar: cal)!
        check(try store.claim(future), "future occurrence claim")
        check(try !store.claim(repeated), "clock rollback cannot replay pruned older occurrence")
        try Data("broken".utf8).write(to: dir.appendingPathComponent("occurrences.json"))
        do { _ = try store.claim(edited); fatalError("corrupt ledger allowed a start") }
        catch ScheduleOccurrenceStore.StoreError.corruptLedger { assertions += 1 }

        var state = ScheduleHandoff<Int>.Occupancy.idle
        var terminal: ScheduleHandoff<Int>.Terminal?
        var starts = [Int]()
        var stops = 0
        var reports = [(ScheduleOccurrence.Result, String)]()
        var valid = true
        let handoff = ScheduleHandoff<Int>(timeout: .milliseconds(120), occupancy: { state },
            terminal: { terminal }, stop: { stops += 1 }, start: { snapshot in
                starts.append(snapshot); return .started(id)
            }, isCurrent: { _ in valid }, report: { _, result, reason, _ in reports.append((result, reason)) })
        handoff.submit(repeated, force: false, snapshot: 1)
        try await Task.sleep(for: .milliseconds(20))
        check(starts == [1] && stops == 0 && reports.last?.0 == .started, "idle starts once")
        state = .tool
        handoff.submit(repeated, force: true, snapshot: 2)
        check(starts == [1] && stops == 0 && reports.last?.1 == "utilityTaskBusy", "force leaves utility alone")
        state = .daily(id)
        handoff.submit(repeated, force: false, snapshot: 3)
        check(stops == 0 && reports.last?.1 == "dailyTaskBusy", "ordinary schedule skips daily")
        handoff.submit(repeated, force: true, snapshot: 4)
        try await Task.sleep(for: .milliseconds(20))
        check(stops == 1 && starts == [1], "waits for actual terminal")
        state = .idle; terminal = .init(id: id, cleanupSucceeded: true)
        try await Task.sleep(for: .milliseconds(60))
        check(starts == [1, 4], "frozen snapshot starts after cleanup")
        state = .daily(id)
        handoff.submit(repeated, force: true, snapshot: 5)
        try await Task.sleep(for: .milliseconds(150))
        state = .idle; terminal = .init(id: id, cleanupSucceeded: true)
        try await Task.sleep(for: .milliseconds(60))
        check(starts == [1, 4] && reports.last?.1 == "handoffTimedOut", "late stop never revives timed out intent")
        state = .daily(id)
        handoff.submit(repeated, force: true, snapshot: 6)
        try await Task.sleep(for: .milliseconds(10))
        handoff.cancelPending()
        state = .idle
        try await Task.sleep(for: .milliseconds(60))
        check(starts == [1, 4] && reports.last?.0 == .cancelled, "user cancel")
        state = .daily(id)
        handoff.submit(repeated, force: true, snapshot: 7)
        valid = false; handoff.invalidateIfNeeded(); state = .idle
        try await Task.sleep(for: .milliseconds(60))
        check(starts == [1, 4] && reports.last?.1 == "scheduleChanged", "edited/deleted intent cancelled")
        valid = true; state = .daily(id)
        handoff.submit(repeated, force: true, snapshot: 8)
        try await Task.sleep(for: .milliseconds(10))
        terminal = .init(id: id, cleanupSucceeded: false); state = .idle
        try await Task.sleep(for: .milliseconds(60))
        check(starts == [1, 4] && reports.last?.1 == "cleanupFailed", "failed cleanup never restarts")
        valid = true; state = .idle
        let failedStart = ScheduleHandoff<Int>(occupancy: { .idle }, terminal: { nil }, stop: {},
            start: { _ in .failed }, isCurrent: { _ in true },
            report: { _, result, reason, _ in reports.append((result, reason)) })
        failedStart.submit(repeated, force: false, snapshot: 1)
        try await Task.sleep(for: .milliseconds(10))
        check(reports.last?.0 == .failed, "start failure reported")
        let stopError = ScheduleHandoff<Int>(occupancy: { .daily(id) }, terminal: { nil },
            stop: { throw CancellationError() }, start: { _ in fatalError("stop failure starts") },
            isCurrent: { _ in true }, report: { _, result, reason, _ in reports.append((result, reason)) })
        stopError.submit(repeated, force: true, snapshot: 1)
        try await Task.sleep(for: .milliseconds(10))
        check(reports.last?.1 == "stopFailed", "stop failure reported")
        print("PASS: \(assertions) scheduling assertions")
    }
}
