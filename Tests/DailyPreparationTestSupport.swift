import Combine
import Foundation
import Observation

// Only the external core/connection and unrelated configuration are replaced.
// Entry-point bodies, state declarations, menu predicate and bridge come from production.
@MainActor final class Gate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var entered = false
    func wait() async {
        entered = true
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        continuation?.resume()
        continuation = nil
    }
}

enum FixtureError: Error { case connection }
enum MAATaskType { case Copilot, SSSCopilot, ParadoxCopilot, Recruit, Depot, VideoRecognition, OperBox, Custom }
@MainActor final class Core {
    var isRunning = false
    var runningGate: Gate?
    var runningReturnsSnapshot = false
    var running: Bool {
        get async {
            let snapshot = isRunning
            let gate = runningGate
            runningGate = nil
            if let gate { await gate.wait() }
            return runningReturnsSnapshot ? snapshot : isRunning
        }
    }
    var queued = [UUID]()
    var failAppendAt: Int?
    var startCount = 0
    var appendCount = 0
    var stopCount = 0
    var preStartGate: Gate?
    var startGate: Gate?
    var stopGate: Gate?
    var failStart = false
    var failStop = false
    func appendTask(type: MAATaskType, params: String) async throws -> Int32 {
        appendCount += 1
        return Int32(appendCount)
    }
    func appendTask(_ task: DailyTask.Kind) async throws -> Int32 {
        appendCount += 1
        if appendCount == failAppendAt { throw FixtureError.connection }
        queued.append(UUID())
        return Int32(appendCount)
    }
    func start() async throws {
        startCount += 1
        if let preStartGate { await preStartGate.wait() }
        if failStart { throw FixtureError.connection }
        isRunning = true
        if let startGate { await startGate.wait() }
    }
    func stop() async throws {
        stopCount += 1
        if let stopGate { await stopGate.wait() }
        if failStop { throw FixtureError.connection }
        isRunning = false
        queued.removeAll()
    }
}
struct RecruitConfiguration {
    var params: Self { self }
    func jsonString() throws -> String { "{}" }
}
struct VideoRecognitionConfiguration {
    let filename: String
    var params: String? { "{}" }
}
@MainActor final class TestLogStore {
    var taskStartTime: Date?
    var screencapCost: Int?
    var lastScreencapWarningLevel = 0
    var hasPrintedFPSHighTip = false
    var sanityReport: Int?
    var fightReport: Int?
    var stoneUsedTimes = 0
    var recruitConfirmTimes = 0
    func setDailyTasksDetailMode(_ mode: MAAViewModel.DailyTasksDetailMode) {}
}
enum ClientChannel { case official }
enum TouchMode { case MacPlayTools, maatouch }
struct GameConfiguration {
    var client_type = ClientChannel.official
    var start_game_enabled = false
}
struct DailyTask {
    enum Kind {
        case startup(GameConfiguration)
        case closedown(GameConfiguration)
        case fixture
    }
    var id = UUID()
    var task: Kind
    var enabled = true
}
@MainActor final class MAAViewModel: ObservableObject {
    let dailyRunCoordinator = DailyRunCoordinator()
    private var dailyRunOutcome = DailyRunOutcome.completed
    private(set) var dailyRunTasks: [DailyTask]?
    var dailyTaskProfile = "Fixture"
    func logError(verbatim value: String) { errors.append(value) }
    // PRODUCTION_MODEL_MEMBERS
    enum DailyTasksDetailMode { case log }
    struct DailyTaskTimer {
        var id = UUID()
        var uniqueKey: String { id.uuidString }
    }
    var medicineUsedTimes = 0
    var expiringMedicineUsedTimes = 0
    var handle: Core? = Core()
    var logStore: TestLogStore? = TestLogStore()
    var tasks: [DailyTask] = []
    var clientChannel = ClientChannel.official
    var touchMode = TouchMode.maatouch
    var taskIDMap: [Int32: UUID] = [:]
    var taskStatus: [UUID: Int] = [:]
    var messageTask: Task<Void, Never>?
    var achievementEvents = AchievementEventAdapter()
    func startGame(client: ClientChannel) async -> Bool { true }
    var recruitConfig = RecruitConfiguration()
    var connectionGate: Gate?
    var failConnection = false
    var makeCoreBusyDuringEnsure = false
    var ensureCount = 0
    var errors = [String]()
    var infos = [String]()
    var operationInFlightForTest: Bool { isStartStopInFlight }
    func reportIdleCallback() { resetStatus() }
    func reportBusyCallback() { status = .busy }
    func logError(_ text: String) { errors.append(text) }
    func logInfo(_ text: String) { infos.append(text) }
    func ensureHandle(requireConnect: Bool = true) async throws {
        ensureCount += 1
        if handle == nil { handle = Core() }
        if makeCoreBusyDuringEnsure { handle?.isRunning = true }
        // PRODUCTION_CORE_RUNNING_GUARD
        if let connectionGate { await connectionGate.wait() }
        if failConnection { throw FixtureError.connection }
    }

}


typealias MAATask = DailyTask.Kind
struct AchievementEventAdapter { mutating func register(taskID: Int32, runID: UUID) {} }
struct AchievementEvent { enum Metric { case scheduledStart }; let runID: UUID?; let metric: Metric }
@MainActor final class AchievementStore { static let shared = AchievementStore(); func record(_ event: AchievementEvent) {} }
