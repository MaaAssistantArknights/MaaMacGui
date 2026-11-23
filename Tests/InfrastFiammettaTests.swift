import Foundation

func check(_ condition: Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(condition, "Fiammetta configuration regression", file: file, line: line)
}
let defaults = InfrastConfiguration.defaultFiammettaTargets
check(defaults == ["清流", "可露希尔", "但书"])
let samples: [([String]?, [String])] = [
    (nil, defaults), ([], []), (["", "  "], []), (["unknown", "Purestream"], []),
    (["清流"], ["清流"]), ([" 但书 ", "清流", "但书", ""], ["但书", "清流"]),
    (["巫恋", "龙舌兰", "歌蕾蒂娅", "清流"], ["巫恋", "龙舌兰", "歌蕾蒂娅"]),
    (["unknown", "可露希尔"], ["可露希尔"]),
]
var count = 0
for mode in [0, 10000, 20000] {
    for enabled in [nil, false, true] as [Bool?] {
        for (inputTargets, normalized) in samples {
            let old: [String: Any] = [
                "mode": mode, "facility": ["Dorm", "Mfg"], "drones": "Money", "threshold": 0.6, "replenish": true,
                "dorm_notstationed_enabled": true, "dorm_trust_enabled": true, "continue_training": false,
                "reception_message_board": false, "filename": "plan.json", "plan_index": 3,
            ]
            var input = old
            if let enabled { input["fiammetta_recovery_enabled"] = enabled }
            if let inputTargets { input["fiammetta_targets"] = inputTargets }
            let config = try JSONDecoder().decode(
                InfrastConfiguration.self, from: JSONSerialization.data(withJSONObject: input))
            let effective = mode == 0 && (enabled ?? false) && !normalized.isEmpty
            check(config.fiammetta_targets == normalized)
            check(config.fiammetta_recovery_enabled == ((enabled ?? false) && !normalized.isEmpty))
            let actual = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config.params)) as! NSDictionary
            var expected = old
            expected["fiammetta_recovery_enabled"] = effective
            expected["fiammetta_targets"] = effective ? normalized : []
            check(actual == expected as NSDictionary)
            check(
                try PropertyListDecoder().decode(InfrastConfiguration.self, from: PropertyListEncoder().encode(config))
                    == config)
            check(try JSONDecoder().decode(InfrastConfiguration.self, from: JSONEncoder().encode(config)) == config)
            count += 1
        }
    }
}
var config = InfrastConfiguration()
check(!config.fiammetta_recovery_enabled && config.fiammetta_targets == defaults)
config.fiammetta_recovery_enabled = true
for mode in [InfrastConfiguration.Mode.default, .custom, .rotation, .default] {
    config.mode = mode
    check(config.params.fiammetta_recovery_enabled == (mode == .default))
    check(config.params.fiammetta_targets == (mode == .default ? defaults : []))
    check(config.fiammetta_recovery_enabled && config.fiammetta_targets == defaults)
}
config.fiammetta_targets = []
check(!config.params.fiammetta_recovery_enabled && config.params.fiammetta_targets.isEmpty)
for mode in [0, 10000, 20000] {
    let old: [String: Any] = [
        "enable": true, "mode": mode, "facility": ["Dorm"], "drones": "_NotUse", "threshold": 0.3, "replenish": false,
        "dorm_notstationed_enabled": false, "dorm_trust_enabled": true, "filename": "plan.json", "plan_index": 1,
    ]
    let legacy = try JSONDecoder().decode(
        LegacyInfrastConfiguration.self, from: JSONSerialization.data(withJSONObject: old))
    let migrated = InfrastConfiguration(migrating: legacy)
    check(!migrated.fiammetta_recovery_enabled && migrated.fiammetta_targets == defaults)
    check(migrated.mode.rawValue == mode && migrated.facility == [.Dorm] && migrated.dorm_trust_enabled)
}
if let sourcePath = CommandLine.arguments.dropFirst().first {
    let source = try String(contentsOfFile: sourcePath, encoding: .utf8)
    func coreNames(_ name: String) throws -> [String] {
        let declaration = try NSRegularExpression(pattern: "\(name) = \\{([^}]+)\\}")
        let match = declaration.firstMatch(in: source, range: NSRange(source.startIndex..., in: source))!
        let body = String(source[Range(match.range(at: 1), in: source)!])
        return try NSRegularExpression(pattern: "\"([^\"]+)\"").matches(
            in: body, range: NSRange(body.startIndex..., in: body)
        ).map {
            String(body[Range($0.range(at: 1), in: body)!])
        }
    }
    check(try coreNames("SupportedFiammettaTargets") == InfrastConfiguration.FiammettaTarget.allCases.map(\.rawValue))
    check(try coreNames("DefaultFiammettaTargets") == defaults)
    print("PASS: allowed/default target lists match supplied Core source")
}
print(
    "PASS: \(count) mode/enablement/missing-empty-invalid target combinations; JSON/plist, mode restoration and actual legacy migration"
)
