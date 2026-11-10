import Foundation

/// Typed names so renames cannot silently break the observer/post pairs.
extension Notification.Name {
    static let MAACancelPendingScheduledStart = Notification.Name("MAACancelPendingScheduledStart")
    static let MAADailyRunFinished = Notification.Name("MAADailyRunFinished")
}

/// Shared identity and terminal contract for daily automation entry points.
enum DailyRunOrigin: String, Codable { case manual, schedule, hotkey }
enum DailyRunPhase: String, Codable { case preparing, preHook, connecting, running, stopping, postHook, finished }
enum DailyRunOutcome: String, Codable { case completed, cancelled, failed, interrupted }

struct RunContext: Codable, Equatable, Identifiable {
    let id: UUID
    let origin: DailyRunOrigin
    let profileID: String
    var status: DailyRunPhase
    let startedAt: Date
    var finishedAt: Date?
    var outcome: DailyRunOutcome?
    var cleanupSucceeded: Bool?
}

struct DailyRunSnapshot {
    let profileID: String
    let tasks: [DailyTask]
}

/// One owner for a daily run, retained through post-run cleanup.
@MainActor
final class DailyRunCoordinator {
    private(set) var active: RunContext?
    private(set) var lastTerminal: RunContext?
    /// True while the on-disk journal no longer accepts writes. The in-memory
    /// contract still holds, but the terminal record needs an escape hatch.
    /// Diagnostic only: nothing reads this flag yet. It is reset on every
    /// successful persist (begin/transition/finish) so one failed run cannot
    /// report a stale failure for the next healthy run.
    private(set) var journalPersistFailed = false
    private let journalURL: URL?
    var didChange: (() -> Void)?

    init(journalURL: URL? = nil) {
        self.journalURL = journalURL
        guard let journalURL, let data = try? Data(contentsOf: journalURL),
              var previous = try? JSONDecoder().decode(RunContext.self, from: data) else { return }
        if previous.status != .finished {
            previous.status = .finished
            previous.outcome = .interrupted
            previous.finishedAt = .now
            previous.cleanupSucceeded = nil
        }
        lastTerminal = previous
        // Recovery is reported, never replayed: the script may already have run.
    }

    @discardableResult
    func begin(profileID: String, origin: DailyRunOrigin) throws -> UUID? {
        guard active == nil else { return nil }
        let context = RunContext(id: UUID(), origin: origin, profileID: profileID,
                                 status: .preparing, startedAt: .now)
        try persist(context)
        journalPersistFailed = false
        active = context
        didChange?()
        return context.id
    }

    func transition(_ phase: DailyRunPhase, for id: UUID) throws {
        guard var context = active, context.id == id, context.status != .postHook else { return }
        context.status = phase
        try persist(context)
        journalPersistFailed = false
        active = context
        didChange?()
    }

    @discardableResult
    func finish(_ id: UUID, outcome: DailyRunOutcome, cleanupSucceeded: Bool?) throws -> Bool {
        guard var context = active, context.id == id else { return false }
        context.status = .finished
        context.finishedAt = .now
        context.outcome = outcome
        context.cleanupSucceeded = cleanupSucceeded
        try persist(context)
        journalPersistFailed = false
        lastTerminal = context
        active = nil
        didChange?()
        NotificationCenter.default.post(name: .MAADailyRunFinished, object: context)
        return true
    }

    /// User escape hatch while the journal cannot be written: finish the run in
    /// memory only so stop/start are not refused until an app restart. The stale
    /// on-disk record is still marked interrupted by the next launch.
    @discardableResult
    func abandon(_ id: UUID, outcome: DailyRunOutcome = .cancelled) -> Bool {
        guard var context = active, context.id == id else { return false }
        journalPersistFailed = true
        context.status = .finished
        context.finishedAt = .now
        context.outcome = outcome
        context.cleanupSucceeded = nil
        lastTerminal = context
        active = nil
        didChange?()
        NotificationCenter.default.post(name: .MAADailyRunFinished, object: context)
        return true
    }

    private func persist(_ context: RunContext) throws {
        guard let journalURL else { return }
        try FileManager.default.createDirectory(at: journalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(context).write(to: journalURL, options: .atomic)
    }
}
