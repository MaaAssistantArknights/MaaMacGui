import Foundation

func check(_ condition: Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(condition, "Award configuration regression", file: file, line: line)
}

func fields(_ config: AwardConfiguration) throws -> [String: Bool] {
    let data = try JSONEncoder().encode(config.params)
    return try JSONDecoder().decode([String: Bool].self, from: data)
}

let oldKeys = ["award", "mail", "recruit", "orundum", "mining", "specialaccess"]
var cases = 0
let empty = AwardConfiguration()
check(!empty.signinevent)
check(try fields(empty) == Dictionary(uniqueKeysWithValues: (oldKeys + ["signinevent"]).map { ($0, $0 == "award") }))

// Exhaust all previous flag combinations. Missing/new flag and legacy migration
// must preserve every old field, including the non-default Award setting.
for bits in 0..<64 {
    let old = Dictionary(uniqueKeysWithValues: oldKeys.enumerated().map { ($0.element, bits & (1 << $0.offset) != 0) })
    let oldJSON = try JSONEncoder().encode(old)
    var config = try JSONDecoder().decode(AwardConfiguration.self, from: oldJSON)
    check(!config.signinevent)
    let oldPlist = try PropertyListEncoder().encode(old)
    check(try PropertyListDecoder().decode(AwardConfiguration.self, from: oldPlist) == config)
    let originalSubtitle = config.subtitle
    for enabled in [true, false] {
        config.signinevent = enabled
        var expected = old
        expected["signinevent"] = enabled
        check(try fields(config) == expected)
        check(try JSONDecoder().decode(AwardConfiguration.self, from: JSONEncoder().encode(config)) == config)
        check(
            try PropertyListDecoder().decode(AwardConfiguration.self, from: PropertyListEncoder().encode(config))
                == config)
        check(
            config.subtitle
                == (enabled
                    ? [originalSubtitle, String(localized: "签到活动")].filter { !$0.isEmpty }.joined(separator: " ")
                    : originalSubtitle))
        // Old readers ignore the new key and retain all six supported fields.
        let legacyReader = try JSONDecoder().decode(
            LegacyAwardConfiguration.self,
            from: JSONEncoder().encode(expected.merging(["enable": true]) { _, new in new }))
        let migrated = AwardConfiguration(migrating: legacyReader)
        var migratedExpected = old
        migratedExpected["signinevent"] = false
        check(try fields(migrated) == migratedExpected)
        cases += 1
    }
}

let nullConfig = try JSONDecoder().decode(AwardConfiguration.self, from: Data("{\"signinevent\":null}".utf8))
check(!nullConfig.signinevent)
do {
    _ = try JSONDecoder().decode(AwardConfiguration.self, from: Data("{\"signinevent\":1}".utf8))
    fatalError("Invalid signinevent type must be rejected")
} catch DecodingError.typeMismatch {}
print("PASS: \(cases) flag/migration/JSON/plist combinations; empty/null defaults and invalid type")
