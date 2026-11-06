import Foundation

func check(_ condition: Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(condition, "Recruit configuration regression", file: file, line: line)
}

func decode(_ value: [String: Any]) throws -> RecruitConfiguration {
    try JSONDecoder().decode(RecruitConfiguration.self, from: JSONSerialization.data(withJSONObject: value))
}

func params(_ config: RecruitConfiguration) throws -> NSDictionary {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(config.params)) as! NSDictionary
}

let robot = "支援机械"
let dps = "输出"
let healing = "治疗"
let defaults = RecruitConfiguration()
check(defaults.first_tags.isEmpty && !defaults.first_tags_enabled)
check(defaults.preserve_tags == [robot] && defaults.preserve_tags_enabled)
var count = 0
for oldFlag in [nil, false, true] as [Bool?] {
    for explicitTags in [nil, [], [healing, "", " \(dps) ", healing]] as [[String]?] {
        for firstEnabled in [nil, false, true] as [Bool?] {
            for preserveEnabled in [nil, false, true] as [Bool?] {
                var input: [String: Any] = ["first_tags": ["", " \(dps) ", healing, dps]]
                if let oldFlag { input["skip_robot"] = oldFlag }
                if let explicitTags { input["preserve_tags"] = explicitTags }
                if let firstEnabled { input["first_tags_enabled"] = firstEnabled }
                if let preserveEnabled { input["preserve_tags_enabled"] = preserveEnabled }
                let config = try decode(input)
                let expectedPreserve =
                    explicitTags.map(RecruitConfiguration.normalizedTags) ?? ((oldFlag ?? true) ? [robot] : [])
                check(config.first_tags == [dps, healing])
                check(config.first_tags_enabled == (firstEnabled ?? true))
                check(config.preserve_tags == expectedPreserve)
                check(config.preserve_tags_enabled == (preserveEnabled ?? !expectedPreserve.isEmpty))
                let actual = try params(config)
                check(actual["first_tags"] as! [String] == (config.first_tags_enabled ? [dps, healing] : []))
                check(actual["preserve_tags"] as! [String] == (config.preserve_tags_enabled ? expectedPreserve : []))
                check(
                    actual["first_tags_enabled"] == nil && actual["preserve_tags_enabled"] == nil
                        && actual["skip_robot"] == nil)
                check(actual.count == 16)
                check(actual["select"] as! [Int] == [4, 5])
                check(actual["confirm"] as! [Int] == [3, 4, 5])
                check(actual["times"] as! Int == 4 && actual["expedite"] as! Bool == false)
                check(try JSONDecoder().decode(RecruitConfiguration.self, from: JSONEncoder().encode(config)) == config)
                check(
                    try PropertyListDecoder().decode(
                        RecruitConfiguration.self, from: PropertyListEncoder().encode(config)) == config)
                count += 1
            }
        }
    }
}

// Disabled selections persist without participating in effective parameters.
var config = defaults
config.first_tags = [dps, dps, "", " \(healing) "]
config.preserve_tags = [healing, dps, healing]
config.first_tags_enabled = false
config.preserve_tags_enabled = false
let disabled = try PropertyListDecoder().decode(RecruitConfiguration.self, from: PropertyListEncoder().encode(config))
check(disabled.first_tags == [dps, healing] && disabled.preserve_tags == [healing, dps])
check(try params(disabled)["preserve_tags"] as! [String] == [])
config.first_tags_enabled = true
config.preserve_tags_enabled = true
check(try params(config)["first_tags"] as! [String] == [dps, healing])
check(try params(config)["preserve_tags"] as! [String] == [healing, dps])

for skipRobot in [false, true] {
    let old: [String: Any] = [
        "enable": true, "refresh": true, "select": [4, 5, 6], "confirm": [3], "times": 1, "set_time": false,
        "expedite": false, "skip_robot": skipRobot, "recruitment_time": ["3": 460],
    ]
    let legacy = try JSONDecoder().decode(
        LegacyRecruitConfiguration.self, from: JSONSerialization.data(withJSONObject: old))
    let migrated = RecruitConfiguration(migrating: legacy)
    check(migrated.preserve_tags == (skipRobot ? [robot] : []))
    check(migrated.preserve_tags_enabled == skipRobot)
    check(migrated.refresh && migrated.select == [4, 5, 6] && migrated.confirm == [3])
    check(migrated.times == 1 && !migrated.set_time && !migrated.expedite && migrated.recruitment_time == ["3": 460])
}
let recognition = RecruitConfiguration.recognition
check(recognition.select == [4, 5, 6] && recognition.confirm == [-1])
check(recognition.times == 0 && !recognition.refresh && !recognition.expedite && recognition.expedite_times == 0)
check(recognition.preserve_tags == [robot] && recognition.preserve_tags_enabled)

// Both parameter paths (daily tasks and recognition) map first_tags through the
// effective tag names, while preserve_tags always stay canonical IDs.
var recognitionPreferred = recognition
recognitionPreferred.first_tags = [dps]
recognitionPreferred.first_tags_enabled = true
let recognitionParams = recognitionPreferred.params(tagNames: [dps: "DPS"])
check(recognitionParams.first_tags == ["DPS"])
check(recognitionParams.preserve_tags == [robot])
check(recognition.params(tagNames: [dps: "DPS"]).first_tags == [])

// Resource-derived translated labels never become stored protocol IDs.
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(
    at: temporary.appendingPathComponent("global/YoStarEN/resource"), withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }
try JSONSerialization.data(withJSONObject: ["tags": [robot: robot, healing: healing]]).write(
    to: temporary.appendingPathComponent("recruitment.json"))
try JSONSerialization.data(withJSONObject: ["tags": [robot: "Robot", "unrecognized": "Ignored"]]).write(
    to: temporary.appendingPathComponent("global/YoStarEN/resource/recruitment.json"))
let english = RecruitTagCatalog.load(resourceDirectory: temporary, languageCode: "en")
check(english.tags == [robot, healing].sorted())
check(english.label(for: robot) == "Robot" && english.label(for: healing) == healing)
check(english.label(for: "future-tag") == "future-tag")
check(RecruitTagCatalog.load(resourceDirectory: nil, languageCode: "en").tags.isEmpty)
check(RecruitTagCatalog.load(resourceDirectory: temporary, languageCode: "ko").label(for: robot) == robot)
check(try params(recognition)["preserve_tags"] as! [String] == [robot])

// The catalog follows the effective resource directory instead of the bundle,
// so tags introduced by user/OTA resources stay selectable.
let newTag = "新手"
let bundledDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
let updatedDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
defer {
    try? FileManager.default.removeItem(at: bundledDirectory)
    try? FileManager.default.removeItem(at: updatedDirectory)
}
for directory in [bundledDirectory, updatedDirectory] {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
}
try JSONSerialization.data(withJSONObject: ["tags": [robot: robot]]).write(
    to: bundledDirectory.appendingPathComponent("recruitment.json"))
try JSONSerialization.data(withJSONObject: ["tags": [robot: robot, newTag: newTag]]).write(
    to: updatedDirectory.appendingPathComponent("recruitment.json"))
check(RecruitTagCatalog.load(resourceDirectory: bundledDirectory, languageCode: "zh").tags == [robot])
check(
    RecruitTagCatalog.load(resourceDirectory: updatedDirectory, languageCode: "zh").tags == [
        robot, newTag
    ].sorted())
print(
    "PASS: \(count) migration/enablement combinations; retention, normalization, legacy, recognition and resource labels"
)

// Channel-specific tables become the catalog root on global servers, so tags
// only present there remain selectable.
let globalOnlyTag = "远程位"
let channelDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
defer { try? FileManager.default.removeItem(at: channelDirectory) }
try FileManager.default.createDirectory(at: channelDirectory, withIntermediateDirectories: true)
try JSONSerialization.data(withJSONObject: ["tags": [robot: "Robot", globalOnlyTag: "Ranged"]]).write(
    to: channelDirectory.appendingPathComponent("recruitment.json"))
let channelCatalog = RecruitTagCatalog.load(resourceDirectory: channelDirectory, languageCode: "zh")
check(channelCatalog.tags == [robot, globalOnlyTag].sorted())
check(channelCatalog.label(for: robot) == "Robot" && channelCatalog.label(for: globalOnlyTag) == "Ranged")
print("PASS: channel-specific table as catalog root")

// The effective table file follows Core's custom-first order, so in-place
// updates are detectable through its modification date.
let tableDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: tableDirectory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tableDirectory) }
check(RecruitTagCatalog.effectiveTableFile(resourceDirectory: tableDirectory) == nil)
let baseTable = tableDirectory.appendingPathComponent("recruitment.json")
try JSONSerialization.data(withJSONObject: ["tags": [robot: robot]]).write(to: baseTable)
check(RecruitTagCatalog.effectiveTableFile(resourceDirectory: tableDirectory) == baseTable)
let customTable = tableDirectory.appendingPathComponent("recruitment_custom.json")
try JSONSerialization.data(withJSONObject: ["tags": [dps: dps]]).write(to: customTable)
check(RecruitTagCatalog.effectiveTableFile(resourceDirectory: tableDirectory) == customTable)

// Same-path resource updates change the catalog, so reload tokens must not
// rely on the directory path alone.
try JSONSerialization.data(withJSONObject: ["tags": [robot: robot, newTag: newTag]]).write(to: baseTable)
check(RecruitTagCatalog.load(resourceDirectory: tableDirectory, languageCode: "zh").tags == [dps])
try FileManager.default.removeItem(at: customTable)
check(
    RecruitTagCatalog.load(resourceDirectory: tableDirectory, languageCode: "zh").tags == [
        robot, newTag
    ].sorted())
print("PASS: effective table file and same-path table updates")

if let resourcePath = CommandLine.arguments.dropFirst().first {
    let resourceURL = URL(fileURLWithPath: resourcePath)
    let canonical = RecruitTagCatalog.load(resourceDirectory: resourceURL, languageCode: "zh")
    check(!canonical.tags.isEmpty)
    for language in ["en", "ko", "ja"] {
        let catalog = RecruitTagCatalog.load(resourceDirectory: resourceURL, languageCode: language)
        check(catalog.tags == canonical.tags)
        check(catalog.label(for: robot) != robot)
        var preferred = RecruitConfiguration()
        preferred.first_tags_enabled = true
        preferred.first_tags = [dps, healing]
        check(
            preferred.params(tagNames: catalog.labels).first_tags == [
                catalog.label(for: dps), catalog.label(for: healing),
            ])
        check(preferred.params(tagNames: catalog.labels).preserve_tags == [robot])
        check(preferred.first_tags == [dps, healing])
    }
    print("PASS: actual Core resources, \(canonical.tags.count) canonical tags across zh/en/ko/ja")
}

let custom = temporary.appendingPathComponent("recruitment_custom.json")
try JSONSerialization.data(withJSONObject: ["tags": [dps: "Custom DPS"]]).write(to: custom)
check(RecruitTagCatalog.read(resourceDirectory: temporary)?.labels == [dps: "Custom DPS"])
try FileManager.default.removeItem(at: temporary.appendingPathComponent("recruitment.json"))
check(RecruitTagCatalog.read(resourceDirectory: temporary)?.labels == [dps: "Custom DPS"])
var customConfig = RecruitConfiguration()
customConfig.first_tags_enabled = true
customConfig.first_tags = [dps]
check(
    customConfig.params(tagNames: RecruitTagCatalog.read(resourceDirectory: temporary)!.labels).first_tags == [
        "Custom DPS"
    ])
print("PASS: Core custom replacement and custom-only resource overlays")
