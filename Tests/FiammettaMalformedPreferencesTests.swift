import Foundation

func testMalformedPreferences() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let profileURL = directory.appendingPathComponent("Malformed.plist")
    let backupURL = directory.appendingPathComponent("FiammettaPreferences/Malformed.plist")
    let store = DailyTaskProfileStore(profileURL: profileURL)
    let id = UUID()
    var original = InfrastConfiguration()
    original.threshold = 0.8
    original.facility = [.Trade, .Dorm]
    original.filename = "preserved-plan.json"
    original.fiammetta_recovery_enabled = true
    original.fiammetta_targets = ["龙舌兰", "巫恋"]
    let originalTasks = [DailyTask(id: id, task: .infrast(original), enabled: false)]

    let targetInputs: [(Any?, [String])] = [
        (nil, InfrastConfiguration.defaultFiammettaTargets), (["但书"], ["但书"]), ([], []),
        ("巫恋", []), (42, []), (true, []), (["巫恋", 42] as [Any], []), (["name": "巫恋"], []),
    ]
    let enabledInputs: [(Any?, Bool)] = [
        (nil, false), (true, true), (false, false), ("true", false), (42, false), ([], false),
        (["enabled": true], false),
    ]
    var count = 0
    for (inputTargets, expectedTargets) in targetInputs {
        for (inputEnabled, expectedEnabled) in enabledInputs {
            var fields = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
            fields["fiammetta_targets"] = inputTargets
            fields["fiammetta_recovery_enabled"] = inputEnabled

            func verify(_ tasks: [DailyTask], targets: [String], enabled: Bool) throws {
                var expected = original
                expected.fiammetta_targets = targets
                expected.fiammetta_recovery_enabled = enabled && !targets.isEmpty
                check(tasks == [DailyTask(id: id, task: .infrast(expected), enabled: false)])
                // Match the startup load -> immediate write-back -> restart path.
                try store.save(tasks)
                check(try store.load() == tasks)
            }

            for json in [true, false] {
                let data =
                    try json
                    ? JSONSerialization.data(withJSONObject: fields)
                    : PropertyListSerialization.data(fromPropertyList: fields, format: .binary, options: 0)
                let config =
                    try json
                    ? JSONDecoder().decode(InfrastConfiguration.self, from: data)
                    : PropertyListDecoder().decode(InfrastConfiguration.self, from: data)
                try verify(
                    [DailyTask(id: id, task: .infrast(config), enabled: false)],
                    targets: expectedTargets, enabled: expectedEnabled)
                count += 1
            }

            var records =
                try PropertyListSerialization.propertyList(
                    from: PropertyListEncoder().encode(originalTasks), format: nil) as! [[String: Any]]
            records[0]["task"] = ["infrast": ["_0": fields]]
            let profile = try PropertyListSerialization.data(fromPropertyList: records, format: .binary, options: 0)

            // Without a backup, one malformed preference cannot discard the task.
            try FileManager.default.removeItem(at: backupURL)
            try profile.write(to: profileURL)
            try verify(store.load(), targets: expectedTargets, enabled: expectedEnabled)

            // With a valid stale backup, only absent fields are restored. A bad
            // explicit value must never re-enable recovery from that backup.
            try store.save(originalTasks)
            try profile.write(to: profileURL)
            try verify(
                store.load(),
                targets: inputTargets == nil ? original.fiammetta_targets : expectedTargets,
                enabled: inputEnabled == nil ? true : expectedEnabled)

            // The same malformed fields in the sidecar must decode safely too,
            // without dropping other preferences in this record.
            var missingFields = fields
            missingFields.removeValue(forKey: "fiammetta_targets")
            missingFields.removeValue(forKey: "fiammetta_recovery_enabled")
            records[0]["task"] = ["infrast": ["_0": missingFields]]
            try PropertyListSerialization.data(fromPropertyList: records, format: .binary, options: 0)
                .write(to: profileURL)
            try PropertyListSerialization.data(
                fromPropertyList: [id.uuidString: fields], format: .binary, options: 0
            ).write(to: backupURL)
            try verify(store.load(), targets: expectedTargets, enabled: expectedEnabled)
            count += 3
        }
    }

    // Explicit JSON null is malformed rather than a missing preference.
    let nullData = Data("{\"fiammetta_targets\":null,\"fiammetta_recovery_enabled\":true}".utf8)
    let nullConfig = try JSONDecoder().decode(InfrastConfiguration.self, from: nullData)
    check(nullConfig.fiammetta_targets.isEmpty && !nullConfig.fiammetta_recovery_enabled)
    print("PASS: \(count) malformed/missing/valid field cases across JSON, plist, inline/backup recovery and restart")
}

try testMalformedPreferences()
