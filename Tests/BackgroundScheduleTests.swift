import Foundation
@main struct BackgroundScheduleTests {
    static var checks = 0
    static func check(_ condition: Bool, _ message: String) { checks += 1; if !condition { fatalError(message) } }
    static func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    static func main() throws {
        if CommandLine.arguments.count == 3 {
            let directory = URL(fileURLWithPath: CommandLine.arguments[2])
            let files = BackgroundScheduleFiles(directory: directory)
            let plans = [1, 2].map { DailyTaskSchedule(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0))!, hour: 9, minute: 0, isEnabled: true) }
            if CommandLine.arguments[1] == "--setup" {
                try files.publish(SchedulePublication(revision: UUID(), enabled: true, profileID: "Default", plans: plans, publishedAt: .now))
                return
            }
            if CommandLine.arguments[1] == "--accept" {
                let intent = try files.intents().first!.1
                let accepted = try ScheduleOccurrenceStore(directory: directory).acceptBackgroundIntent(intent.occurrence)
                print(accepted ? "accepted" : "duplicate")
                return
            }
            if CommandLine.arguments[1] == "--race" {
                var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                let delivered = try BackgroundScheduleCheck(files: files, ledger: ScheduleOccurrenceStore(directory: directory)).perform(now: date("2026-10-29T09:00:30Z"), calendar: calendar)
                print(delivered ? "delivered" : "duplicate")
                return
            }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = BackgroundScheduleFiles(directory: directory)
        let ledger = ScheduleOccurrenceStore(directory: directory)
        let checker = BackgroundScheduleCheck(files: files, ledger: ledger)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let first = DailyTaskSchedule(id: firstID, hour: 9, minute: 0, isEnabled: true)
        let second = DailyTaskSchedule(id: secondID, hour: 9, minute: 0, isEnabled: true, forceStart: true)
        var publication = SchedulePublication(revision: UUID(), enabled: false, profileID: "Default", plans: [second, first], publishedAt: .now)
        try files.publish(publication)
        check(try !checker.perform(now: date("2026-10-29T09:00:30Z"), calendar: calendar), "disabled does not wake")
        publication = SchedulePublication(revision: UUID(), enabled: true, profileID: "Default", plans: [second, first], publishedAt: .now)
        try files.publish(publication)
        check(try checker.perform(now: date("2026-10-29T09:00:30Z"), calendar: calendar), "publishes one intent")
        let intents = try files.intents()
        check(intents.count == 1 && intents[0].1.occurrence.planID == firstID, "stable same minute winner")
        check(try ledger.records().first(where: { $0.planID == secondID })?.result == .skipped, "loser explicitly skipped")
        check(try !checker.perform(now: date("2026-10-29T09:00:45Z"), calendar: calendar), "duplicate check does not wake again")
        let intent = intents[0].1
        check(intent.isValid(in: publication, now: date("2026-10-29T09:05:00Z"), calendar: calendar), "five minutes accepted")
        check(!intent.isValid(in: publication, now: date("2026-10-29T09:05:01Z"), calendar: calendar), "expired rejected")
        check(!intent.isValid(in: publication, now: date("2026-10-29T08:59:59Z"), calendar: calendar), "future intent rejected")
        let differentProfile = SchedulePublication(revision: UUID(), enabled: true, profileID: "Other", plans: [first], publishedAt: .now)
        check(!intent.isValid(in: differentProfile, now: date("2026-10-29T09:01:00Z"), calendar: calendar), "changed profile rejected")
        let removed = SchedulePublication(revision: UUID(), enabled: true, profileID: "Default", plans: [], publishedAt: .now)
        check(!intent.isValid(in: removed, now: date("2026-10-29T09:01:00Z"), calendar: calendar), "deleted plan rejected")
        var edited = first; edited.forceStart = true
        let changed = SchedulePublication(revision: UUID(), enabled: true, profileID: "Default", plans: [edited], publishedAt: .now)
        check(!intent.isValid(in: changed, now: date("2026-10-29T09:01:00Z"), calendar: calendar), "stale revision rejected")
        try ledger.recoverInterrupted(now: date("2026-10-29T09:01:00Z"))
        check(try ledger.records().first(where: { $0.planID == firstID })?.result == .pending, "helper claim survives GUI cold start")
        check(try ledger.acceptBackgroundIntent(intent.occurrence), "one GUI accepts helper claim")
        check(try !ledger.acceptBackgroundIntent(intent.occurrence), "second GUI cannot accept same envelope")
        try ledger.recoverInterrupted()
        check(try ledger.records().first(where: { $0.planID == firstID })?.result == .interrupted, "accepted unknown run is not replayed")
        check(try !checker.perform(now: date("2026-10-30T09:05:01Z"), calendar: calendar), "expired occurrence not delivered")
        check(try ledger.records().filter { $0.result == .missed && $0.id.contains(":2026-10-30:") }.count == 2, "expired records missed")
        let before = try ledger.records().count
        check(try !checker.perform(now: date("2026-10-29T09:01:00Z"), calendar: calendar), "clock rollback no replay")
        check(try ledger.records().count == before, "rollback stable")
        check(try checker.perform(now: date("2026-10-31T09:00:30Z"), calendar: calendar), "new date remains runnable")
        try ledger.expireUndeliveredBackgroundIntents(now: date("2026-10-31T09:05:01Z"))
        check(try ledger.records().contains(where: { $0.detail == "backgroundIntentExpired" && $0.result == .missed }), "undelivered intent expires")
        try Data("{bad".utf8).write(to: files.inboxURL.appendingPathComponent("0000.json"))
        do { _ = try files.intents(); fatalError("broken inbox accepted") } catch { checks += 1 }
        check(try files.intents().count == 2, "corrupt envelope does not permanently block valid inbox")
        let legacyDirectory = directory.appendingPathComponent("Legacy")
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        try Data("{\"schemaVersion\":1,\"records\":{}}".utf8).write(to: legacyDirectory.appendingPathComponent("occurrences.json"))
        let legacyStore = ScheduleOccurrenceStore(directory: legacyDirectory)
        check(try legacyStore.records().isEmpty, "old C5 ledger without date watermarks migrates")
        var processed = intent.occurrence; processed.result = .completed; processed.detail = ""
        _ = try legacyStore.claim(processed)
        let migration = ScheduleOccurrenceStore(directory: directory.appendingPathComponent("Migration"))
        _ = try migration.claim(intent.occurrence)
        try migration.mergeHistory(from: legacyStore)
        check(try migration.records().first?.result == .completed, "processed foreground history wins over an undelivered helper claim")
        check(try !migration.claim(intent.occurrence), "migration cannot replay processed occurrence")
        // GUI and helper share the same production candidate/claim function.
        for guiFirst in [true, false] {
            let raceDirectory = directory.appendingPathComponent(guiFirst ? "GUIFirst" : "AgentFirst")
            let raceFiles = BackgroundScheduleFiles(directory: raceDirectory)
            let raceLedger = ScheduleOccurrenceStore(directory: raceDirectory)
            let raceCheck = BackgroundScheduleCheck(files: raceFiles, ledger: raceLedger)
            try raceFiles.publish(publication)
            let late = date("2026-10-29T09:01:30Z")
            if guiFirst {
                check(try BackgroundScheduleCheck.claimDue(plans: publication.plans, now: late, calendar: calendar, grace: 300, ledger: raceLedger, source: "") != nil, "GUI accepts +90s recovery window")
                check(try !raceCheck.perform(now: late, calendar: calendar), "agent cannot claim GUI winner again")
            } else {
                check(try raceCheck.perform(now: late, calendar: calendar), "agent accepts +90s recovery window")
                check(try BackgroundScheduleCheck.claimDue(plans: publication.plans, now: late, calendar: calendar, grace: 300, ledger: raceLedger, source: "") == nil, "GUI cannot promote another plan after agent claim")
            }
        }
        let sequentialFiles = BackgroundScheduleFiles(directory: directory.appendingPathComponent("SequentialMinutes"))
        let sequentialLedger = ScheduleOccurrenceStore(directory: sequentialFiles.directory)
        let sequentialCheck = BackgroundScheduleCheck(files: sequentialFiles, ledger: sequentialLedger)
        let ten = DailyTaskSchedule(id: firstID, hour: 10, minute: 0, isEnabled: true)
        let tenOne = DailyTaskSchedule(id: secondID, hour: 10, minute: 1, isEnabled: true)
        let tenOneLoser = DailyTaskSchedule(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, hour: 10, minute: 1, isEnabled: true)
        try sequentialFiles.publish(SchedulePublication(revision: UUID(), enabled: true, profileID: "Default", plans: [tenOneLoser,tenOne,ten], publishedAt:.now))
        let tenIntent = try sequentialCheck.performIntent(now: date("2026-10-29T10:00:01Z"), calendar: calendar)!
        try sequentialLedger.update(tenIntent.occurrence.id, result: .completed)
        let tenOneIntent = try sequentialCheck.performIntent(now: date("2026-10-29T10:01:01Z"), calendar: calendar)
        check(tenOneIntent?.occurrence.planID == secondID, "completed previous minute does not suppress the next minute")
        check(try sequentialLedger.records().contains(where: { $0.planID == tenOneLoser.id && $0.result == .skipped }), "same-minute loser remains skipped")
        check(try !sequentialCheck.perform(now: date("2026-10-29T10:01:02Z"), calendar: calendar), "same-minute loser is never promoted")
        let recoveryFiles = BackgroundScheduleFiles(directory: directory.appendingPathComponent("RecoveryLimit"))
        let recoveryLedger = ScheduleOccurrenceStore(directory: recoveryFiles.directory)
        let recoveryCheck = BackgroundScheduleCheck(files: recoveryFiles, ledger: recoveryLedger)
        try recoveryFiles.publish(SchedulePublication(revision: UUID(), enabled: true, profileID: "Default", plans: [ten,tenOne], publishedAt:.now))
        check(try recoveryCheck.perform(now: date("2026-10-29T10:02:01Z"), calendar: calendar), "one historical minute recovers after wake")
        check(try !recoveryCheck.perform(now: date("2026-10-29T10:02:02Z"), calendar: calendar), "same wake does not rotate through historical minutes")
        check(try recoveryLedger.records().contains(where: { $0.detail == "recoveryBatchLimit" && $0.result == .skipped }), "remaining historical minutes recorded skipped")
        let ledgerFile = recoveryFiles.directory.appendingPathComponent("occurrences.json")
        let sentinel = Date(timeIntervalSince1970: 42)
        try FileManager.default.setAttributes([.modificationDate: sentinel], ofItemAtPath: ledgerFile.path)
        _ = try recoveryLedger.records()
        try recoveryLedger.expireUndeliveredBackgroundIntents(now: date("2026-10-29T10:02:03Z"))
        check(try FileManager.default.attributesOfItem(atPath: ledgerFile.path)[.modificationDate] as? Date == sentinel, "read and empty expiry do not rewrite unchanged ledger")
        let midnightFiles = BackgroundScheduleFiles(directory: directory.appendingPathComponent("Midnight"))
        let midnightLedger = ScheduleOccurrenceStore(directory: midnightFiles.directory)
        let midnightCheck = BackgroundScheduleCheck(files: midnightFiles, ledger: midnightLedger)
        let latePlan = DailyTaskSchedule(id: UUID(), hour: 23, minute: 59, isEnabled: true)
        try midnightFiles.publish(SchedulePublication(revision: UUID(), enabled: true, profileID: "Default", plans: [latePlan], publishedAt: .now))
        let midnightIntent = try midnightCheck.performIntent(now: date("2026-10-30T00:01:00Z"), calendar: calendar)
        check(midnightIntent?.occurrence.scheduledAt == date("2026-10-29T23:59:00Z"), "previous local day catches up after two minutes")
        check(try !midnightCheck.perform(now: date("2026-10-31T00:05:01Z"), calendar: calendar), "previous local day outside five minutes is missed")
        let wakeFiles = BackgroundScheduleFiles(directory: directory.appendingPathComponent("WakeFailure"))
        let wakeLedger = ScheduleOccurrenceStore(directory: wakeFiles.directory)
        let wakeCheck = BackgroundScheduleCheck(files: wakeFiles, ledger: wakeLedger)
        try wakeFiles.publish(publication)
        let wakeIntent = try wakeCheck.performIntent(now: date("2026-10-29T09:00:30Z"), calendar: calendar)!
        try wakeCheck.recordWakeFailure(wakeIntent)
        check(try wakeLedger.records().contains(where: { $0.result == .failed && $0.detail == "wakeFailed" }), "wake failure is visible in ledger")
        check(try FileManager.default.contentsOfDirectory(atPath: wakeFiles.directory.appendingPathComponent("FailedIntents").path).count == 1, "failed wake retains intent evidence")
        check(try !wakeCheck.perform(now: date("2026-10-29T09:01:00Z"), calendar: calendar), "wake failure never reclaims same occurrence")
        let malformedFiles = BackgroundScheduleFiles(directory: directory.appendingPathComponent("BrokenInbox"))
        let malformedLedger = ScheduleOccurrenceStore(directory: malformedFiles.directory)
        let malformedCheck = BackgroundScheduleCheck(files: malformedFiles, ledger: malformedLedger)
        try malformedFiles.publish(publication)
        try Data().write(to: malformedFiles.inboxURL)
        do { _ = try malformedCheck.perform(now: date("2026-10-29T09:00:30Z"), calendar: calendar); fatalError("broken inbox delivered") } catch { checks += 1 }
        check(try malformedLedger.records().contains(where: { $0.result == .failed && $0.detail == "intentWriteFailed" }), "intent delivery failure is visible")
        let application = directory.appendingPathComponent("Test.app")
        let macOS = application.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let info = ["CFBundleIdentifier":"com.hguandl.MeoAsstMac", "CFBundleExecutable":"MAA", "CFBundlePackageType":"APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: application.appendingPathComponent("Contents/Info.plist"))
        try Data().write(to: macOS.appendingPathComponent("MAA"))
        try Data().write(to: macOS.appendingPathComponent("MAAScheduleAgent"))
        check(try ScheduleAgentLocation.containingApplication(executable: macOS.appendingPathComponent("MAAScheduleAgent")) == application.resolvingSymlinksInPath(), "helper uses exact containing application")
        do { _ = try ScheduleAgentLocation.containingApplication(executable: macOS.appendingPathComponent("Other")); fatalError("foreign executable accepted") } catch { checks += 1 }
        try Data("{broken".utf8).write(to: files.publicationURL)
        do { _ = try checker.perform(now: .now, calendar: calendar); fatalError("broken publication accepted") } catch { checks += 1 }
        var unsupported = publication; unsupported.schemaVersion = 2
        do { try files.publish(unsupported); fatalError("unsupported schema accepted") } catch { checks += 1 }
        let duplicateIDs = SchedulePublication(revision: UUID(), enabled: true, profileID: "Default", plans: [first,first], publishedAt: .now)
        do { try duplicateIDs.validate(); fatalError("duplicate plans accepted") } catch { checks += 1 }
        print("PASS: \(checks) background scheduling assertions")
    }
}
