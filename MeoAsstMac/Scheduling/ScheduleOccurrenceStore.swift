import Darwin
import Foundation

/// One ledger and lock are shared by all trigger sources. Atomic replacement
/// protects readers from partial writes; flock protects the read/modify/write.
final class ScheduleOccurrenceStore: @unchecked Sendable {
    struct Ledger: Codable, Equatable {
        var schemaVersion = 1
        var records: [String: ScheduleOccurrence] = [:]
        var latestLocalDates: [String: String] = [:]

        init() {}
        private enum CodingKeys: String, CodingKey { case schemaVersion, records, latestLocalDates }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
            records = try values.decode([String: ScheduleOccurrence].self, forKey: .records)
            latestLocalDates = try values.decodeIfPresent([String: String].self, forKey: .latestLocalDates) ?? [:]
        }
    }

    enum StoreError: Error { case lockFailed, unsupportedSchema, corruptLedger, capacityReached }
    let directory: URL
    private let retention = 4096

    init(directory: URL) { self.directory = directory }

    func records() throws -> [ScheduleOccurrence] {
        try transaction { ledger in Array(ledger.records.values).sorted { $0.updatedAt > $1.updatedAt } }
    }

    /// Never silently discard a corrupt ledger: doing so could replay a task.
    @discardableResult
    func claim(_ occurrence: ScheduleOccurrence) throws -> Bool {
        try transaction { ledger in try insert(occurrence, into: &ledger) }
    }

    /// One lock covers recovery selection and all same-wake skipped records.
    /// A second trigger source cannot claim another historical minute between
    /// selecting the first recovery and recording the remainder as skipped.
    func claimDueGroups(_ groups: [[ScheduleOccurrence]]) throws -> ScheduleOccurrence? {
        try transaction { ledger in
            var selected: ScheduleOccurrence?
            for group in groups {
                guard let first = group.first else { continue }
                let previousWinner = ledger.records.values.first {
                    $0.scheduledAt == first.scheduledAt && $0.detail != "simultaneousSchedule"
                }
                for (index, var occurrence) in group.enumerated() {
                    if index > 0 || previousWinner != nil {
                        if ledger.records[occurrence.id] != nil { continue }
                        occurrence.result = .skipped
                        occurrence.detail = "simultaneousSchedule"
                        _ = try insert(occurrence, into: &ledger)
                    } else if selected == nil {
                        if try insert(occurrence, into: &ledger) { selected = occurrence }
                    } else {
                        occurrence.result = .skipped
                        occurrence.detail = "recoveryBatchLimit"
                        _ = try insert(occurrence, into: &ledger)
                    }
                }
            }
            return selected
        }
    }

    private func insert(_ occurrence: ScheduleOccurrence, into ledger: inout Ledger) throws -> Bool {
        guard ledger.records[occurrence.id] == nil else { return false }
        let planKey = occurrence.planID.uuidString
        let localDate = occurrence.id.split(separator: ":").dropFirst().first.map(String.init)
        if let localDate, let latest = ledger.latestLocalDates[planKey], localDate < latest { return false }
        let cutoff = occurrence.updatedAt.addingTimeInterval(-14 * 86400)
        ledger.records = ledger.records.filter { $0.value.updatedAt >= cutoff }
        guard ledger.records.count < retention else { throw StoreError.capacityReached }
        ledger.records[occurrence.id] = occurrence
        if let localDate { ledger.latestLocalDates[planKey] = max(localDate, ledger.latestLocalDates[planKey] ?? localDate) }
        return true
    }

    func update(_ id: String, result: ScheduleOccurrence.Result, detail: String = "",
                runID: UUID? = nil, now: Date = .now) throws {
        try transaction { ledger in
            guard var record = ledger.records[id] else { return }
            record.result = result
            record.detail = detail
            record.runID = runID ?? record.runID
            record.updatedAt = now
            ledger.records[id] = record
        }
    }

    func recoverInterrupted(now: Date = .now) throws {
        try transaction { ledger in
            for (id, var record) in ledger.records where record.result == .started ||
                (record.result == .pending && record.detail != "backgroundIntent") {
                record.result = .interrupted
                record.detail = "previousRunOutcomeUnknown"
                record.updatedAt = now
                ledger.records[id] = record
            }
        }
    }

    /// Imports the foreground history before connecting the GUI scheduler.
    /// Existing shared claims always win; no recent claim is discarded.
    func mergeHistory(from source: ScheduleOccurrenceStore) throws {
        let imported = try source.transaction { $0 }
        try transaction { ledger in
            for (id, record) in imported.records {
                if ledger.records[id] == nil || (ledger.records[id]?.result == .pending && record.result != .pending) {
                    ledger.records[id] = record
                }
            }
            guard ledger.records.count <= retention else { throw StoreError.capacityReached }
            for (plan, date) in imported.latestLocalDates {
                ledger.latestLocalDates[plan] = max(date, ledger.latestLocalDates[plan] ?? date)
            }
        }
    }

    @discardableResult
    func expireUndeliveredBackgroundIntents(now: Date = .now) throws -> Bool {
        try transaction { ledger in
            var expired = false
            for (id, var record) in ledger.records where record.result == .pending &&
                record.detail == "backgroundIntent" && record.expiresAt < now {
                record.result = .missed
                record.detail = "backgroundIntentExpired"
                record.updatedAt = now
                ledger.records[id] = record
                expired = true
            }
            return expired
        }
    }

    /// Transfers the helper's claim to one GUI consumer under the same lock.
    /// Matching the full envelope rejects corrupted or forged inbox files.
    func acceptBackgroundIntent(_ occurrence: ScheduleOccurrence, now: Date = .now) throws -> Bool {
        try transaction { ledger in
            guard var record = ledger.records[occurrence.id], record == occurrence,
                  record.result == .pending, record.detail == "backgroundIntent" else { return false }
            record.detail = "guiAccepted"
            record.updatedAt = now
            ledger.records[record.id] = record
            return true
        }
    }

    func rejectBackgroundIntent(_ id: String, result: ScheduleOccurrence.Result, detail: String, now: Date = .now) throws {
        try transaction { ledger in
            guard var record = ledger.records[id], record.result == .pending,
                  record.detail == "backgroundIntent" else { return }
            record.result = result
            record.detail = detail
            record.updatedAt = now
            ledger.records[id] = record
        }
    }

    private func transaction<T>(_ operation: (inout Ledger) throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lockURL = directory.appendingPathComponent("occurrences.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw StoreError.lockFailed }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw StoreError.lockFailed }
        defer { flock(descriptor, LOCK_UN) }
        let file = directory.appendingPathComponent("occurrences.json")
        var ledger: Ledger
        if FileManager.default.fileExists(atPath: file.path) {
            do { ledger = try JSONDecoder().decode(Ledger.self, from: Data(contentsOf: file)) }
            catch { throw StoreError.corruptLedger }
            guard ledger.schemaVersion == 1 else { throw StoreError.unsupportedSchema }
        } else {
            ledger = Ledger()
        }
        let original = ledger
        let result = try operation(&ledger)
        if ledger != original { try JSONEncoder().encode(ledger).write(to: file, options: .atomic) }
        return result
    }
}
