import Foundation

@main struct RunProfilePatchTests {
    @MainActor static func main() throws {
        var checks = 0
        func check(_ value: Bool, _ name: String) {
            checks += 1
            if !value { fatalError(name) }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("maa-run-profile-patch-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), otherID = UUID()
        let old = Date(timeIntervalSince1970: 100), event = Date(timeIntervalSince1970: 200), edited = Date(timeIntervalSince1970: 300)
        var mall = MallConfiguration(); mall.creditFightDate = old; mall.friendVisitDate = old; mall.buy_first = ["Original A"]
        let frozen = DailyTask(id: id, task: .mall(mall), enabled: true)
        var clone = mall; clone.buy_first = ["Unrelated B"]; clone.creditFightDate = edited
        let b = [DailyTask(id: id, task: .mall(clone), enabled: false)]
        let aURL = root.appendingPathComponent("A.plist"), bURL = root.appendingPathComponent("B.plist")
        func save(_ value: [DailyTask], _ url: URL) throws { try PropertyListEncoder().encode(value).write(to: url, options: .atomic) }
        func load(_ url: URL) throws -> [DailyTask] { try PropertyListDecoder().decode([DailyTask].self, from: Data(contentsOf: url)) }
        func configure(_ original: DailyTask) throws -> MAAViewModel {
            let model = MAAViewModel(directory: root)
            model.dailyRunTasks = [original]
            model.tasks = b
            model.taskIDMap[42] = id
            let runID = try model.dailyRunCoordinator.begin(profileID: "A", origin: .schedule)!
            try model.dailyRunCoordinator.transition(.running, for: runID)
            return model
        }
        try save([frozen], aURL); try save(b, bURL)
        let bBefore = try Data(contentsOf: bURL)
        let model = try configure(frozen)
        check(model.applyDailyTaskCallback(.creditFightDate(event), coreID: 42), "patch original profile")
        guard case .mall(let saved) = try load(aURL)[0].task else { fatalError() }
        check(saved.creditFightDate == event && saved.buy_first == ["Original A"], "target field changed in A")
        let bAfter = try Data(contentsOf: bURL)
        check(model.tasks == b && bAfter == bBefore, "same UUID clone B untouched")
        guard case .mall(let updatedSnapshot) = model.dailyRunTasks![0].task else { fatalError() }
        check(updatedSnapshot.creditFightDate == event, "snapshot callback field synchronized")
        check(!model.applyDailyTaskCallback(.friendVisitDate(event), coreID: 99), "foreign callback rejected")
        check(!model.applyDailyTaskCallback(.friendVisitDate(event), coreID: nil), "missing task ID rejected")

        var otherEdit = mall; otherEdit.shopping = false; otherEdit.buy_first = ["User edited A"]
        try save([DailyTask(id: id, task: .mall(otherEdit), enabled: false), DailyTask(id: otherID, task: .mall(clone), enabled: true)], aURL)
        let preserving = try configure(frozen)
        check(preserving.applyDailyTaskCallback(.friendVisitDate(event), coreID: 42), "preserve other saved edits")
        let preservedTasks = try load(aURL)
        guard case .mall(let preserved) = preservedTasks[0].task else { fatalError() }
        check(!preserved.shopping && preserved.buy_first == ["User edited A"] && preserved.friendVisitDate == event, "patch only specified field")
        check(!preservedTasks[0].enabled && preservedTasks.count == 2 && preservedTasks[1].id == otherID, "preserve enable and other tasks")
        guard case .mall(let stillFrozen) = preserving.dailyRunTasks![0].task else { fatalError() }
        check(stillFrozen.buy_first == ["Original A"] && stillFrozen.friendVisitDate == event, "snapshot keeps original execution fields")

        var sameFieldEdit = mall; sameFieldEdit.creditFightDate = edited
        try save([DailyTask(id: id, task: .mall(sameFieldEdit), enabled: true)], aURL)
        let conflictBytes = try Data(contentsOf: aURL)
        let conflicting = try configure(frozen)
        check(!conflicting.applyDailyTaskCallback(.creditFightDate(event), coreID: 42), "user same-field edit wins")
        check(try Data(contentsOf: aURL) == conflictBytes, "conflict performs no write")
        check(conflicting.dailyRunTasks == [frozen], "conflict does not advance snapshot")

        let selected = try configure(frozen); selected.dailyTaskProfile = "A"
        selected.tasks = [DailyTask(id: id, task: .mall(otherEdit), enabled: false)]
        check(selected.applyDailyTaskCallback(.creditFightDate(event), coreID: 42), "selected origin uses latest UI")
        guard case .mall(let latestUI) = selected.tasks[0].task else { fatalError() }
        check(latestUI.creditFightDate == event && !latestUI.shopping && latestUI.buy_first == ["User edited A"], "UI preserves other edits")
        check(try load(aURL) == selected.tasks, "origin disk and matching UI synchronized")
        check(!selected.isApplyingDailyCallbackPatch, "write-back suppression released")
        selected.tasks = [DailyTask(id: id, task: .mall(sameFieldEdit), enabled: true)]
        check(!selected.applyDailyTaskCallback(.creditFightDate(.now), coreID: 42), "selected same-field edit respected")

        var infrast = InfrastConfiguration(); infrast.mode = .custom; infrast.filename = "Plan A"; infrast.plan_index = 0
        let infraFrozen = DailyTask(id: id, task: .infrast(infrast), enabled: true)
        var infraEdit = infrast; infraEdit.threshold = 0.75
        try save([DailyTask(id: id, task: .infrast(infraEdit), enabled: true)], aURL)
        let rotation = try configure(infraFrozen)
        check(rotation.applyDailyTaskCallback(.infrastructurePlanIndex(1), coreID: 42), "infrastructure plan advances")
        guard case .infrast(let rotated) = try load(aURL)[0].task else { fatalError() }
        check(rotated.plan_index == 1 && rotated.threshold == 0.75, "rotation preserves user threshold")
        infraEdit.plan_index = 2
        try save([DailyTask(id: id, task: .infrast(infraEdit), enabled: true)], aURL)
        check(!rotation.applyDailyTaskCallback(.infrastructurePlanIndex(2), coreID: 42), "user plan-index edit wins")
        infraEdit.plan_index = 1; infraEdit.filename = "Other plan"
        try save([DailyTask(id: id, task: .infrast(infraEdit), enabled: true)], aURL)
        check(!rotation.applyDailyTaskCallback(.infrastructurePlanIndex(2), coreID: 42), "changed plan file not rotated")
        try FileManager.default.removeItem(at: aURL)
        check(!rotation.applyDailyTaskCallback(.infrastructurePlanIndex(2), coreID: 42), "deleted original profile not recreated")
        check(!FileManager.default.fileExists(atPath: aURL.path), "deleted profile stays deleted")
        try Data("corrupt".utf8).write(to: aURL)
        check(!rotation.applyDailyTaskCallback(.infrastructurePlanIndex(2), coreID: 42), "bad profile not replaced by frozen snapshot")
        check(try Data(contentsOf: aURL) == Data("corrupt".utf8), "bad file preserved for recovery")
        let runID = rotation.dailyRunCoordinator.active!.id
        try rotation.dailyRunCoordinator.transition(.postHook, for: runID)
        check(!rotation.applyDailyTaskCallback(.infrastructurePlanIndex(2), coreID: 42), "late callback after core terminal rejected")
        print("RunProfilePatchTests: \(checks) assertions passed")
    }
}
