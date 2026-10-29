import Combine
import Foundation
import Observation

let hookTestSuite = "MAAHookLifecycleTests-\(ProcessInfo.processInfo.processIdentifier)"

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
        return Int32(appendCount)
    }
    func start() async throws {
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
    func clearLogs() {}
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
    let hookSettings = HookSettingsStore(defaults: UserDefaults(suiteName: hookTestSuite)!)
    private var runHookConfiguration = HookConfiguration()
    private var dailyStartCancelled = false
    private var activeHookTask: Task<HookResult, Error>?
    private var runTerminationDeadline: Date?
    @Published private(set) var isTestingHook = false
    func setTestingHookForTest(_ value: Bool) { isTestingHook = value }
    var dailyTaskProfile = "Fixture"
    static let userDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("MAAHookLifecycleTests")
    var adbPath = "/usr/bin/true"
    func logError(verbatim value: String) { errors.append(value) }
    func logInfo(verbatim value: String) { infos.append(value) }
    func logTrace(verbatim value: String) {}
    func logWarn(verbatim value: String) {}
    func logWarn(_ value: String) {}
    init() {
        // PRODUCTION_DAILY_RUN_CHANGE
    }
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
    func ensureHandle(requireConnect: Bool = true, clearLogs: Bool = true) async throws {
        ensureCount += 1
        if handle == nil { handle = Core() }
        if makeCoreBusyDuringEnsure { handle?.isRunning = true }
        // PRODUCTION_CORE_RUNNING_GUARD
        if let connectionGate { await connectionGate.wait() }
        if failConnection { throw FixtureError.connection }
    }

}

enum CopilotCategory { case list, bundled }
enum CopilotKind { case regular, sss, paradox }
struct CopilotSet { var kind = CopilotKind.regular }
struct CopilotItem {
    var isOn = true
    var url = URL(filePath: "/fixture.json")
    var isRaid: Bool?
}
enum CopilotContent {
    case copilot(URL, CopilotKind, Bool)
    case invalid
}
struct CopilotConfiguration {
    struct Item {
        var filename: String
        var nav_name_override: String?
        var is_raid: Bool
    }
    var filename: String?
    var copilot_list: [Item] = []
    var failEncoding = false
    func jsonString() throws -> String {
        if failEncoding { throw FixtureError.connection }
        return "{}"
    }
}
struct CopilotContext {
    var config = CopilotConfiguration()
    var category = CopilotCategory.bundled
    var copilotSet: CopilotSet? = CopilotSet()
    var copilotList = [CopilotItem]()
    var content = CopilotContent.copilot(URL(filePath: "/fixture.json"), .regular, false)
}
@Observable final class NewViewModel {
    let parent: MAAViewModel
    var copilot = CopilotContext()
    private(set) var copilotStartToken: UUID?
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    // PRODUCTION_BRIDGE_STATE
    @MainActor init(parent: MAAViewModel) {
        self.parent = parent
        // PRODUCTION_BRIDGE_SUBSCRIPTIONS
    }
    // PRODUCTION_COPILOT_BRIDGE
}

final class ObservationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() {
        lock.lock()
        defer { lock.unlock() }
        value = true
    }
    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
