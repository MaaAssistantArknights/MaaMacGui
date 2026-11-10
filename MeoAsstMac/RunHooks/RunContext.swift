import Foundation

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
    private let journalURL: URL?
    /// 首次写盘失败后置位：本次会话其余生命周期仅在内存中跟踪运行。日志
    /// 故障绝不楔死运行——占用必须仍可释放、stop 必须仍可执行；磁盘上停
    /// 留的过期内容由 init 的 interrupted 恢复语义兜底。
    private(set) var journalDegraded = false
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
        // 降级后仍要开跑：定时触发此刻已被认领，因日志故障拒绝启动会白白
        // 丢失一次执行。
        do { try persist(context) } catch {}
        active = context
        didChange?()
        return context.id
    }

    func transition(_ phase: DailyRunPhase, for id: UUID) throws {
        guard var context = active, context.id == id, context.status != .postHook else { return }
        context.status = phase
        // 相位必须在内存中照常推进（含降级后），否则一次写盘失败会阻断
        // stop()/启动收尾并泄漏占用（r3 A-P2-1）。
        do { try persist(context) } catch {}
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
        // 日志写失败也必须收口（内存降级），否则占用永久无法释放、终态永不
        // 落账；磁盘上的过期内容交给重启后的 interrupted 恢复（r3 A-P2-1）。
        do { try persist(context) } catch {}
        lastTerminal = context
        active = nil
        didChange?()
        NotificationCenter.default.post(name: Notification.Name("MAADailyRunFinished"), object: context)
        return true
    }

    private func persist(_ context: RunContext) throws {
        guard let journalURL, !journalDegraded else { return }
        do {
            try FileManager.default.createDirectory(at: journalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(context).write(to: journalURL, options: .atomic)
        } catch {
            // 降级为内存模式并记一次诊断：后续写不再重试，调用方继续收口。
            journalDegraded = true
            print("Daily run journal degraded to memory mode: \(error)")
            throw error
        }
    }
}
