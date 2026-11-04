import Foundation

extension Encodable {
    func jsonString() throws -> String {
        String(decoding: try JSONEncoder().encode(self), as: UTF8.self)
    }
}

struct QueuedTask {
    let id = UUID()
    var task: MAATask
    var enabled = true
}

struct CallbackInfo {
    let taskid: Int32?
}

final class RecordingHandle {
    var sent: [Int32: Int] = [:]
    var nextID: Int32 = 1

    func appendTask(type: MAATaskType, params: String) async throws -> Int32 {
        let json = try JSONSerialization.jsonObject(with: Data(params.utf8)) as! [String: Any]
        let id = nextID
        nextID += 1
        sent[id] = json["medicine_expire_days"] as? Int
        return id
    }

    func appendTask(_ task: MAATask) async throws -> Int32 {
        switch task {
        case .fight(let config): return try await appendTask(type: .Fight, params: config.params.jsonString())
        }
    }
}

final class MedicineLogHarness {
    var tasks: [QueuedTask] = []
    var taskIDMap: [Int32: UUID] = [:]
    var fightTaskParams: [Int32: FightConfiguration.Params] = [:]
    var taskStatus: [UUID: Bool] = [:]
    var handle: RecordingHandle? = RecordingHandle()
    var clientChannel = MAAClientChannel.Official
    var stageActivity: MAAStageActivity?
    var now = ISO8601DateFormatter().date(from: "2026-10-24T00:00:00Z")!

    func logInfo(_ message: String) {}
    func dailyTask(coreID: Int32?) -> MAATask? {
        guard let coreID, let id = taskIDMap[coreID] else { return nil }
        return tasks.first { $0.id == id }?.task
    }
}

// Matches the production callback localization helper.
// swift-format-ignore: AlwaysUseLowerCamelCase
func L(_ text: LocalizedStringResource) -> String { String(localized: text) }

@main struct MedicineLogTests {
    static func main() async throws {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            guard condition else { fatalError("FAIL: \(message)") }
            checks += 1
        }
        let json = """
            {"miniGame":[],"sideStoryStage":{"event":{"Activity":{"UtcStartTime":"2026/10/22 04:00:00","UtcExpireTime":"2026/10/26 03:59:59","TimeZone":8},"Stages":[{"Value":"TEST-1"}]}}}
            """
        let activity = try JSONDecoder().decode(MAAStageActivity.self, from: Data(json.utf8))
        for baseDays in [0, 1, 2, 7] {
            for enabled in [true, false] {
                let model = MedicineLogHarness()
                model.stageActivity = activity
                var config = FightConfiguration()
                config.medicine_expire_days = baseDays
                config.useActivityMedicine = enabled
                model.tasks = [QueuedTask(task: .fight(config))]
                try await model.enqueue()
                let days = enabled ? max(baseDays, 2) : baseDays
                check(model.handle?.sent[1] == days, "Core receives effective window")
                let expected = days > 0 ? L(configWithDays(days).localizedExpiry) : L("即将")
                check(
                    model.expiryText(coreID: 1) == expected,
                    "log must match sent window; base=\(baseDays), activity=\(enabled)")
                if case .fight(let saved) = model.tasks[0].task {
                    check(saved == config, "preferences keep configured window")
                }
                // A delayed callback must describe its original Core task even
                // after the activity ends, channel changes or task is removed.
                model.now = model.now.addingTimeInterval(7 * 86400)
                model.stageActivity = nil
                model.clientChannel = .YoStarEN
                model.tasks = [QueuedTask(task: .fight(configWithDays(10)))]
                check(model.expiryText(coreID: 1) == expected, "callback uses submitted snapshot")
                model.tasks.removeAll()
                check(model.expiryText(coreID: 1) == expected, "removing preferences cannot change submitted window")
                check(model.expiryText(coreID: nil) == L("即将"), "missing task ID fallback")
                check(model.expiryText(coreID: 999) == L("即将"), "unknown task ID fallback")
                model.resetQueue()
                check(model.expiryText(coreID: 1) == L("即将"), "new queue drops previous snapshot")
                check(model.fightTaskParams.isEmpty, "snapshot reset with task ID map")
            }
        }
        let model = MedicineLogHarness()
        model.stageActivity = activity
        var extended = configWithDays(0)
        extended.useActivityMedicine = true
        model.tasks = [QueuedTask(task: .fight(extended)), QueuedTask(task: .fight(configWithDays(7)))]
        try await model.enqueue()
        check(model.expiryText(coreID: 1) == L(configWithDays(2).localizedExpiry), "first task has extended expiry")
        check(model.expiryText(coreID: 2) == L(configWithDays(7).localizedExpiry), "second task retains its own expiry")
        model.resetQueue()
        model.handle?.nextID = 1
        model.tasks = [QueuedTask(task: .fight(configWithDays(1)))]
        try await model.enqueue()
        check(
            model.expiryText(coreID: 1) == L(configWithDays(1).localizedExpiry), "reused Core ID replaces old snapshot")
        print("PASS: \(checks) production enqueue/callback medicine-log checks")
    }

    static func configWithDays(_ days: Int) -> FightConfiguration {
        var config = FightConfiguration()
        config.medicine_expire_days = days
        return config
    }
}
