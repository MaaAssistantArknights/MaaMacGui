import Foundation

/// Shared by the GUI and the one-shot agent. No Core, game configuration, or
/// executable paths cross this boundary.
struct SchedulePublication: Codable, Equatable, Sendable {
    var schemaVersion = 1
    let revision: UUID
    let enabled: Bool
    let profileID: String
    let plans: [DailyTaskSchedule]
    let publishedAt: Date

    func validate() throws {
        guard schemaVersion == 1, !profileID.isEmpty, profileID.count <= 256,
              plans.count <= 128, Set(plans.map(\.id)).count == plans.count,
              plans.allSatisfy(\.isValid) else { throw BackgroundScheduleError.invalidPublication }
    }
}

struct BackgroundScheduleIntent: Codable, Equatable, Sendable {
    var schemaVersion = 1
    let occurrence: ScheduleOccurrence
    let profileID: String

    func isValid(in publication: SchedulePublication, now: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        guard schemaVersion == 1, publication.schemaVersion == 1, publication.enabled,
              profileID == publication.profileID, occurrence.result == .pending,
              occurrence.scheduledAt <= now, now <= occurrence.expiresAt,
              occurrence.expiresAt.timeIntervalSince(occurrence.scheduledAt) <= 300,
              let plan = publication.plans.first(where: { $0.id == occurrence.planID && $0.isEnabled && $0.revision == occurrence.revision }),
              let expected = ScheduleCalendar.occurrence(for: plan, on: occurrence.scheduledAt, calendar: calendar, grace: 300)
        else { return false }
        return expected.id == occurrence.id && expected.scheduledAt == occurrence.scheduledAt

    }
}

enum BackgroundScheduleError: Error { case invalidPublication, invalidIntent, signingRequired, helperUnavailable }

struct BackgroundScheduleFiles {
    let directory: URL
    var publicationURL: URL { directory.appendingPathComponent("publication.json") }
    var inboxURL: URL { directory.appendingPathComponent("Inbox", isDirectory: true) }

    func publish(_ publication: SchedulePublication) throws {
        try publication.validate()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(publication).write(to: publicationURL, options: .atomic)
    }

    func publication() throws -> SchedulePublication {
        let data = try Data(contentsOf: publicationURL)
        guard data.count <= 256 * 1024 else { throw BackgroundScheduleError.invalidPublication }
        let value = try JSONDecoder().decode(SchedulePublication.self, from: data)
        try value.validate()
        return value
    }

    func deliver(_ intent: BackgroundScheduleIntent) throws {
        guard intent.schemaVersion == 1 else { throw BackgroundScheduleError.invalidIntent }
        try FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)
        // The plan ID and local time are data; a random envelope file name keeps
        // user-editable identity strings out of path construction.
        let file = inboxURL.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        try JSONEncoder().encode(intent).write(to: file, options: .atomic)
    }

    func preserveFailedIntent(_ intent: BackgroundScheduleIntent) throws {
        let failed = directory.appendingPathComponent("FailedIntents", isDirectory: true)
        try FileManager.default.createDirectory(at: failed, withIntermediateDirectories: true)
        try JSONEncoder().encode(intent).write(to: failed.appendingPathComponent(UUID().uuidString).appendingPathExtension("json"), options: .atomic)
    }

    func intents() throws -> [(URL, BackgroundScheduleIntent)] {
        guard FileManager.default.fileExists(atPath: inboxURL.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(at: inboxURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        var result: [(URL, BackgroundScheduleIntent)] = []
        for url in urls.prefix(256) {
            do {
                let data = try Data(contentsOf: url)
                guard data.count <= 16 * 1024 else { throw BackgroundScheduleError.invalidIntent }
                result.append((url, try JSONDecoder().decode(BackgroundScheduleIntent.self, from: data)))
            } catch {
                let quarantine = directory.appendingPathComponent("Quarantine", isDirectory: true)
                try FileManager.default.createDirectory(at: quarantine, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: url, to: quarantine.appendingPathComponent(UUID().uuidString).appendingPathExtension("json"))
                // Surface the bad envelope once; next poll can consume the
                // remaining valid files without silently deleting evidence.
                throw BackgroundScheduleError.invalidIntent
            }
        }
        return result

    }
}
