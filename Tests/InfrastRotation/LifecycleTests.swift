import Foundation

@main struct LifecycleTests {
    @MainActor static func main() async throws {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            checks += 1
            if !condition { fatalError(message) }
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("{\"plans\":[{\"name\":\"B\",\"duration\":1440},{\"name\":\"A\",\"duration\":480}]}".utf8).write(to: file)
        var config = InfrastConfiguration()
        config.mode = .custom
        config.filename = file.path
        config.rotation = InfrastRotation(automatic: true)
        let id = UUID()
        let vm = MAAViewModel()
        vm.tasks = [.init(id: id, task: .infrast(config), enabled: true)]
        func current(_ model: MAAViewModel = vm) -> InfrastConfiguration {
            guard case .infrast(let value) = model.tasks[id] else { fatalError("missing task") }
            return value
        }
        check(vm.handle?.started == false, "no spontaneous start")
        try await vm.submitForTest()
        check(current().rotation?.current?.name == "B", "prepared concrete B")
        check(current().rotation?.current?.status == .prepared, "prepared state")
        vm.updateInfrastAttempt(coreID: 1, status: .running)
        check(current().rotation?.current?.status == .running, "running state")
        vm.finishInfrastRotation(coreID: 1, succeeded: true)
        check(current().plan_index == 1, "advance B to A once")
        check(current().rotation?.automatic == true, "auto selection remains selected")
        check(current().rotation?.lastCompleted?.name == "B", "history is executed B")
        let completed = current()
        vm.finishInfrastRotation(coreID: 1, succeeded: true)
        check(current() == completed, "duplicate callback changes nothing")
        try await vm.submitForTest()
        check(current().rotation?.current?.name == "A", "second submission chooses A")
        vm.finishInfrastRotation(coreID: 2, succeeded: false)
        check(current().rotation?.current?.status == .incomplete, "failure shown")
        check(current().rotation?.lastCompleted?.name == "B", "failure retains success")
        check(current().plan_index == 1, "failure doesn't advance")
        vm.finishInfrastRotation(coreID: 2, succeeded: true)
        check(current().rotation?.lastCompleted?.name == "B", "completion after error ignored")
        try await vm.submitForTest()
        check(current().rotation?.current?.name == "A", "retry same A")
        var edited = current()
        edited.rotation?.automatic = false
        edited.plan_index = 0
        vm.tasks[id] = .infrast(edited)
        vm.finishInfrastRotation(coreID: 3, succeeded: true)
        check(current().rotation?.lastCompleted?.name == "A", "snapshot survives edit")
        check(current().plan_index == 0 && current().rotation?.automatic == false, "manual choice survives completion")
        // Concrete mode still executes the selected plan and follows original sequential completion behavior.
        try await vm.submitForTest()
        vm.finishInfrastRotation(coreID: 4, succeeded: true)
        check(current().rotation?.lastCompleted?.name == "B" && current().plan_index == 1, "manual plan record and original advance")
        edited = current(); edited.rotation?.automatic = true; vm.tasks[id] = .infrast(edited)
        try await vm.submitForTest()
        check(current().rotation?.current?.name == "A", "switching back uses manual success")
        vm.finishPendingInfrastRotations()
        check(current().rotation?.current?.status == .incomplete, "stop pending attempt")
        check(vm.infrastRotationRuns.isEmpty, "stop consumes runs")
        // Failed start must not leave a prepared attempt that looks active.
        vm.handle?.failStart = true
        do { try await vm.submitForTest(); fatalError("start should fail") } catch {}
        check(current().rotation?.current?.status == .incomplete, "submission failure cleans state")
        check(vm.infrastRotationRuns.isEmpty, "failed start consumes runs")
        vm.handle?.failStart = false
        try await vm.submitForTest()
        let before = current()
        vm.dailyTaskProfile = "Other"
        vm.finishInfrastRotation(coreID: 7, succeeded: true)
        check(current() == before, "other profile not overwritten")
        vm.dailyTaskProfile = "Default"
        try await vm.submitForTest()
        try Data("{\"plans\":[{\"name\":\"Changed\"}]}".utf8).write(to: file)
        vm.finishInfrastRotation(coreID: 8, succeeded: true)
        check(current().plan_index == before.plan_index, "edited file doesn't advance")
        let hash = InfrastRotationRun.fingerprint(try Data(contentsOf: file))
        check(current().rotation?.suggestedDate(fingerprint: hash) == nil, "edited file invalidates suggestion")
        print("PASS: \(checks) lifecycle assertions using production submission and callback handlers")
    }
}
