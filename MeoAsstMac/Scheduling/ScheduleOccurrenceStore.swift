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
    private let retention = 512

    init(directory: URL) { self.directory = directory }

    func records() throws -> [ScheduleOccurrence] {
        try transaction { ledger in Array(ledger.records.values).sorted { $0.updatedAt > $1.updatedAt } }
    }

    /// Never silently discard a corrupt ledger: doing so could replay a task.
    @discardableResult
    func claim(_ occurrence: ScheduleOccurrence) throws -> Bool {
        try transaction { ledger in
            guard ledger.records[occurrence.id] == nil else { return false }
            let planKey = occurrence.planID.uuidString
            let localDate = occurrence.id.split(separator: ":").dropFirst().first.map(String.init)
            if let localDate, let latest = ledger.latestLocalDates[planKey], localDate < latest { return false }
            // Never evict a recent claim: a clock rollback or a second trigger
            // source could otherwise replay that occurrence.
            let cutoff = occurrence.updatedAt.addingTimeInterval(-14 * 86400)
            ledger.records = ledger.records.filter { $0.value.updatedAt >= cutoff }
            guard ledger.records.count < retention else { throw StoreError.capacityReached }
            ledger.records[occurrence.id] = occurrence
            if let localDate { ledger.latestLocalDates[planKey] = max(localDate, ledger.latestLocalDates[planKey] ?? localDate) }
            return true
        }
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
            for (id, var record) in ledger.records where record.result == .pending || record.result == .started {
                record.result = .interrupted
                record.detail = "previousRunOutcomeUnknown"
                record.updatedAt = now
                ledger.records[id] = record
            }
        }
    }

    /// Explicit user-confirmed recovery from an unreadable ledger: the file is
    /// removed under the same lock and the next transaction rebuilds an empty
    /// ledger. Claims are forgotten, so an occurrence still inside its grace
    /// window may trigger once more after the reset.
    func resetLedger() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lockURL = directory.appendingPathComponent("occurrences.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw StoreError.lockFailed }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw StoreError.lockFailed }
        defer { flock(descriptor, LOCK_UN) }
        let file = directory.appendingPathComponent("occurrences.json")
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
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
