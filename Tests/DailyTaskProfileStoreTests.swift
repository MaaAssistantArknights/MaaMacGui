import Foundation

// The enum/record shape matches DailyTask's synthesized plist representation.
// The configuration is the frozen, real pre-feature decoder/encoder fixture.
private struct PreFiammettaDailyTask: Codable {
    let id: UUID
    var task: Task
    var enabled: Bool

    enum Task: Codable {
        case infrast(PreFiammettaInfrastConfiguration)
        case closedown(String)
    }
}

func testProfilePersistence() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let taskID = UUID()
    let secondID = UUID()
    let otherID = UUID()
    let profileURL = directory.appendingPathComponent("Default.plist")
    let store = DailyTaskProfileStore(profileURL: profileURL)
    let backupURL = directory.appendingPathComponent("FiammettaPreferences/Default.plist")

    func configuration(_ enabled: Bool, _ targets: [String], mode: InfrastConfiguration.Mode = .default)
        -> InfrastConfiguration
    {
        var config = InfrastConfiguration()
        config.mode = mode
        config.fiammetta_recovery_enabled = enabled && !targets.isEmpty
        config.fiammetta_targets = targets
        return config
    }

    func task(_ config: InfrastConfiguration, id: UUID = taskID) -> DailyTask {
        DailyTask(id: id, task: .infrast(config), enabled: true)
    }

    func writeProfile(_ tasks: [DailyTask]) throws {
        try PropertyListEncoder().encode(tasks).write(to: profileURL, options: .atomic)
    }

    func oldVersionRewrite() throws {
        let data = try Data(contentsOf: profileURL)
        let tasks = try PropertyListDecoder().decode([PreFiammettaDailyTask].self, from: data)
        try PropertyListEncoder().encode(tasks).write(to: profileURL, options: .atomic)
    }

    func removeFields(_ fields: [String]) throws {
        var records =
            try PropertyListSerialization.propertyList(
                from: Data(contentsOf: profileURL), format: nil) as! [[String: Any]]
        for index in records.indices {
            var payload = records[index]["task"] as! [String: Any]
            guard var infrast = payload["infrast"] as? [String: Any] else { continue }
            var config = infrast["_0"] as! [String: Any]
            for key in fields { config.removeValue(forKey: key) }
            infrast["_0"] = config
            payload["infrast"] = infrast
            records[index]["task"] = payload
        }
        try PropertyListSerialization.data(fromPropertyList: records, format: .binary, options: 0)
            .write(to: profileURL)
    }

    let preferenceFields = ["fiammetta_recovery_enabled", "fiammetta_targets"]
    var roundTrips = 0
    for mode in [InfrastConfiguration.Mode.default, .custom, .rotation] {
        for enabled in [false, true] {
            for targets in [["巫恋", "龙舌兰"], ["歌蕾蒂娅", "但书", "清流"], []] {
                let first = configuration(enabled, targets, mode: mode)
                let second = configuration(true, ["但书"], mode: .rotation)
                let tasks = [
                    DailyTask(id: otherID, task: .closedown("unrelated"), enabled: false),
                    task(first), task(second, id: secondID),
                ]
                try store.save(tasks)
                check(try store.load() == tasks)
                let backup = try Data(contentsOf: backupURL)

                // Old startup rewrites immediately; editing and reordering in the
                // old app must also survive without applying preferences by index.
                var old = try PropertyListDecoder().decode(
                    [PreFiammettaDailyTask].self, from: Data(contentsOf: profileURL))
                if case .infrast(var config) = old[1].task {
                    config.threshold = 0.75
                    config.drones = .Money
                    old[1].task = .infrast(config)
                    old[1].enabled = false
                }
                old.reverse()
                try PropertyListEncoder().encode(old).write(to: profileURL, options: .atomic)
                check(try Data(contentsOf: backupURL) == backup)

                // Prove this fixture reproduces the bug without preference recovery.
                let unprotected = try PropertyListDecoder().decode(
                    [DailyTask].self, from: Data(contentsOf: profileURL))
                if case .infrast(let config) = unprotected[0].task {
                    check(!config.fiammetta_recovery_enabled)
                    check(config.fiammetta_targets == InfrastConfiguration.defaultFiammettaTargets)
                } else {
                    check(false)
                }

                var changed = first
                changed.threshold = 0.75
                changed.drones = .Money
                let expected = [
                    task(second, id: secondID),
                    DailyTask(id: taskID, task: .infrast(changed), enabled: false), tasks[0],
                ]
                let restored = try store.load()
                check(restored == expected)
                try store.save(restored)
                try oldVersionRewrite()
                check(try store.load() == expected)
                roundTrips += 1
            }
        }
    }

    let selected = configuration(true, ["巫恋", "龙舌兰"])
    let cleared = configuration(false, [])
    try store.save([task(selected)])
    // Simulate an inline edit/import with an older backup. False and [] win.
    try writeProfile([task(cleared)])
    check(try store.load() == [task(cleared)])
    try removeFields(["fiammetta_targets"])
    check(try store.load() == [task(configuration(false, selected.fiammetta_targets))])
    try writeProfile([task(configuration(false, ["但书"]))])
    try removeFields(["fiammetta_recovery_enabled"])
    check(try store.load() == [task(configuration(true, ["但书"]))])

    // Backups are normalized too; invalid targets cannot activate Core defaults.
    for (input, expected) in [
        (["unknown", " 巫恋 ", "巫恋", "龙舌兰", "歌蕾蒂娅", "清流"], ["巫恋", "龙舌兰", "歌蕾蒂娅"]),
        (["unknown", " "], []),
    ] {
        let backup: [String: Any] = [
            taskID.uuidString: ["fiammetta_recovery_enabled": true, "fiammetta_targets": input]
        ]
        try PropertyListSerialization.data(fromPropertyList: backup, format: .binary, options: 0)
            .write(to: backupURL)
        try writeProfile([task(selected)])
        try removeFields(preferenceFields)
        check(try store.load() == [task(configuration(true, expected))])
    }

    // Same UUID in another profile uses that profile's own preferences.
    try store.save([task(selected)])
    let otherURL = directory.appendingPathComponent("Other.plist")
    let otherStore = DailyTaskProfileStore(profileURL: otherURL)
    let otherSelection = configuration(false, ["歌蕾蒂娅"])
    try otherStore.save([task(otherSelection)])
    try oldVersionRewrite()
    try FileManager.default.copyItem(at: profileURL, to: directory.appendingPathComponent("Fresh.plist"))
    check(try store.load() == [task(selected)])
    // Reuse an actual old-version rewrite for the other profile too.
    let oldOther = try PropertyListDecoder().decode(
        [PreFiammettaDailyTask].self, from: Data(contentsOf: otherURL))
    try PropertyListEncoder().encode(oldOther).write(to: otherURL)
    check(try otherStore.load() == [task(otherSelection)])
    check(
        try DailyTaskProfileStore(profileURL: directory.appendingPathComponent("Fresh.plist")).load()
            == [task(InfrastConfiguration())])

    // A replacement task with a new UUID cannot inherit the removed task's prefs.
    let replacement = task(selected, id: UUID())
    try writeProfile([replacement])
    try oldVersionRewrite()
    check(try store.load() == [task(InfrastConfiguration(), id: replacement.id)])
    try store.save([])
    try writeProfile([task(selected)])
    try oldVersionRewrite()
    check(try store.load() == [task(InfrastConfiguration())])

    // Existing PR profiles without a backup migrate on the first normal save.
    try FileManager.default.removeItem(at: backupURL)
    try writeProfile([task(selected)])
    check(try store.load() == [task(selected)])
    try store.save(store.load())
    try oldVersionRewrite()
    check(try store.load() == [task(selected)])

    // Missing/corrupt backups never discard valid task settings or invent prefs.
    try Data("invalid backup".utf8).write(to: backupURL)
    try writeProfile([task(selected)])
    check(try store.load() == [task(selected)])
    try oldVersionRewrite()
    check(try store.load() == [task(InfrastConfiguration())])
    try FileManager.default.removeItem(at: backupURL)
    check(try store.load() == [task(InfrastConfiguration())])

    // A single corrupted sidecar record only loses its own task's backup.
    try store.save([task(selected), task(configuration(true, ["清流"]), id: secondID)])
    var backupMap =
        try PropertyListSerialization.propertyList(
            from: Data(contentsOf: backupURL), format: nil) as! [String: Any]
    backupMap[secondID.uuidString] = "corrupted record"
    try PropertyListSerialization.data(fromPropertyList: backupMap, format: .binary, options: 0)
        .write(to: backupURL)
    try oldVersionRewrite()
    let healed = [task(selected), task(InfrastConfiguration(), id: secondID)]
    check(try store.load() == healed)
    // The next save replaces the whole sidecar, healing the corrupted record.
    try store.save(healed)
    try oldVersionRewrite()
    check(try store.load() == healed)

    // Backup write errors are surfaced, while the primary save remains readable.
    try FileManager.default.removeItem(at: backupURL.deletingLastPathComponent())
    try Data().write(to: backupURL.deletingLastPathComponent())
    do {
        try store.save([task(selected)])
        check(false)
    } catch {}
    check(try store.load() == [task(selected)])

    print(
        "PASS: \(roundTrips) downgrade round trips (each repeated); task/profile isolation, old edits, "
            + "inline precedence, migration, normalization, per-record sidecar corruption and backup failures"
    )
}

try testProfilePersistence()
