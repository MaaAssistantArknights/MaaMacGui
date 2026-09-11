import Foundation

struct DailyTask {
    let id: UUID
    let task: MAATask
    var enabled: Bool
}
extension Array where Element == DailyTask {
    subscript(_ id: UUID) -> MAATask? {
        get { first { $0.id == id }?.task }
        set {
            if let newValue, let i = firstIndex(where: { $0.id == id }) {
                self[i] = .init(id: id, task: newValue, enabled: self[i].enabled)
            }
        }
    }
}
enum LogResource { case customInfrastPlanIndexAutoSwitch }
@MainActor final class FakeHandle {
    var appended: [MAATask] = []
    var started = false
    var failStart = false
    func appendTask(_ task: MAATask) async throws -> Int32 {
        appended.append(task)
        return Int32(appended.count)
    }
    func start() async throws {
        if failStart { throw CocoaError(.fileReadUnknown) }
        started = true
    }
}
@MainActor final class FakeLogStore { var taskStartTime: Date? }
@MainActor final class MAAViewModel {
    struct Client { var rawValue = "Official" }
    enum Status { case busy }
    var tasks: [DailyTask] = []
    var taskIDMap: [Int32: UUID] = [:]
    var infrastRotationRuns: [Int32: InfrastRotationRun] = [:]
    var dailyTaskProfile = "Default"
    var clientChannel = Client()
    var touchMode = "MacPlayTools"
    var connectionAddress = "test-only"
    var handle: FakeHandle? = FakeHandle()
    var logStore: FakeLogStore? = FakeLogStore()
    var status: Status = .busy
    func logInfo(_ resource: LogResource) {}
    func logInfo(verbatim: String) {}
    func logTrace(verbatim: String) {}
}
