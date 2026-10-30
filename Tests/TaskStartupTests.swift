import Combine
import Foundation

// Only the core and unrelated app dependencies are replaced. The runner compiles
// the unchanged production startTasks() body and FightConfiguration.swift.
typealias MAATaskConfiguration = Codable & Hashable & Sendable

enum MAATaskType: String {
    case Fight
    var description: String { rawValue }
}

struct ClientConfiguration: Codable {
    var client_type = "Official"
    var start_game_enabled = false
}

enum MAATask: Codable {
    case fight(FightConfiguration)
    case startup(ClientConfiguration)
    case closedown(ClientConfiguration)
}

struct DailyTask: Codable {
    let id: UUID
    var task: MAATask
    var enabled: Bool
}

enum MAAError: Error { case gameStartFailed }

@MainActor final class TestHandle {
    var stages = [String]()
    var started = false

    func appendTask(_ task: MAATask) async throws -> Int32 {
        guard case .fight(let config) = task else { return 0 }
        stages.append(config.params.stage)
        return Int32(stages.count)
    }

    func start() async throws { started = true }
}

@MainActor final class MAAViewModel {
    enum Status { case idle, pending, busy }
    enum TouchMode { case adb, MacPlayTools }

    @Published var tasks = [DailyTask]()
    var status = Status.idle
    var touchMode = TouchMode.adb
    var clientChannel = "Official"
    var taskIDMap = [Int32: UUID]()
    var handle: TestHandle? = TestHandle()
    var logStore: TestLogStore?
    var connection: CheckedContinuation<Void, Never>?

    func ensureHandle() async throws {
        await withCheckedContinuation { connection = $0 }
    }

    func startGame(client: String) async -> Bool { true }
    func handleEarlyReturn(backTo: Status) { if status == .pending { status = backTo } }
}

@MainActor final class TestLogStore { var taskStartTime: Date? }

@main struct TaskStartupTests {
    @MainActor static func main() async throws {
        let cases = [(" ap-5 ", "AP-5"), (" \tAnNiHiLaTiOn\n", "Annihilation")]
        var failures = [String]()
        for (input, expected) in cases {
            let model = MAAViewModel()
            let id = UUID()
            let disabledID = UUID()
            let otherID = UUID()
            let config = try JSONDecoder().decode(FightConfiguration.self, from: Data("{\"stage\":\"1-7\"}".utf8))
            model.tasks = [
                .init(id: id, task: .fight(config), enabled: true),
                .init(id: disabledID, task: .fight(config), enabled: false),
                .init(id: otherID, task: .closedown(.init()), enabled: false),
            ]

            // Observe the same @Published emission used by the app's writeBack
            // subscription. This verifies serialized values, not real app I/O.
            var persisted = Data()
            let subscription = model.$tasks.sink { persisted = try! PropertyListEncoder().encode($0) }
            let startup = Task { try await model.runStartupTest() }
            while model.connection == nil { await Task.yield() }

            var edited = config
            edited.stage = input
            model.tasks[0].task = .fight(edited)
            model.tasks[1].task = .fight(edited)
            model.connection?.resume()
            model.connection = nil
            try await startup.value

            let restored = try PropertyListDecoder().decode([DailyTask].self, from: persisted)
            for (label, tasks) in [("UI", model.tasks), ("plist", restored)] {
                for index in 0...1 {
                    guard case .fight(let stored) = tasks[index].task, stored.stage == expected else {
                        failures.append("\(label) stage after connection: \(input.debugDescription), index \(index)")
                        continue
                    }
                }
                if tasks.map(\.id) != [id, disabledID, otherID] || tasks.map(\.enabled) != [true, false, false] {
                    failures.append("\(label) changed task identity or enablement")
                }
                if case .closedown = tasks[2].task {} else { failures.append("\(label) changed non-fight task") }
            }
            if model.handle?.stages != [expected] || model.taskIDMap[1] != id || model.handle?.started != true {
                failures.append("incorrect core payload, task mapping or startup")
            }
            withExtendedLifetime(subscription) {}
        }
        for failure in failures { print("FAIL: \(failure)") }
        guard failures.isEmpty else { exit(1) }
        print("PASS: edits during ensureHandle; UI/plist stages, core payload, task identity and disabled tasks")
    }
}
