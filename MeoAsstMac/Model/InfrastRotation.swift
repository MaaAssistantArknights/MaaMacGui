import CryptoKit
import Foundation

/// GUI-only history. Never sent to MaaCore or used to start a task.
struct InfrastRotation: Codable, Hashable, Sendable {
    var automatic = false
    var intervalMinutes: Double?
    var lastCompleted: Completion?
    var current: Attempt?

    struct Completion: Codable, Hashable, Sendable {
        let runID: UUID
        let fingerprint: String
        let index: Int
        let name: String
        let completedAt: Date
        let durationMinutes: Double?
        let connection: String
    }

    struct Attempt: Codable, Hashable, Sendable {
        enum Status: String, Codable, Sendable { case prepared, running, completed, incomplete }
        let runID: UUID
        let fingerprint: String
        let index: Int
        let name: String
        let connection: String
        var status: Status
    }

    static func validMinutes(_ minutes: Double?) -> Double? {
        guard let minutes, minutes.isFinite, minutes > 0, minutes <= 525_600 else { return nil }
        return minutes
    }

    func nextIndex(fingerprint: String, count: Int, fallback: Int, connection: String? = nil) -> Int? {
        guard count > 0 else { return nil }
        if automatic, let lastCompleted, lastCompleted.fingerprint == fingerprint,
            connection == nil || lastCompleted.connection == connection,
            (0..<count).contains(lastCompleted.index)
        {
            return (lastCompleted.index + 1) % count
        }
        return (0..<count).contains(fallback) ? fallback : 0
    }

    func suggestedDate(fingerprint: String, connection: String? = nil) -> Date? {
        guard let lastCompleted, lastCompleted.fingerprint == fingerprint,
            connection == nil || lastCompleted.connection == connection,
            let minutes = Self.validMinutes(intervalMinutes ?? lastCompleted.durationMinutes)
        else { return nil }
        return lastCompleted.completedAt.addingTimeInterval(minutes * 60)
    }

    /// The caller consumes each run once before invoking this method.
    mutating func complete(_ run: InfrastRotationRun, at date: Date) {
        guard lastCompleted?.runID != run.id else { return }
        lastCompleted = Completion(
            runID: run.id, fingerprint: run.fingerprint, index: run.index, name: run.name,
            completedAt: date, durationMinutes: run.durationMinutes, connection: run.connection)
        current = Attempt(
            runID: run.id, fingerprint: run.fingerprint, index: run.index,
            name: run.name, connection: run.connection, status: .completed)
    }
}

struct InfrastRotationRun: Sendable {
    let id: UUID
    let profile: String
    let connection: String
    let filename: String
    let fingerprint: String
    let index: Int
    let count: Int
    let name: String
    let durationMinutes: Double?
    let automatic: Bool
    let selectedIndex: Int
    let descriptionPost: String?

    static func fingerprint(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
