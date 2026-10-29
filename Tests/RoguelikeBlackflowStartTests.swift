import Foundation

var checks = 0
func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    precondition(value(), message)
}
func params(_ config: RoguelikeConfiguration, supported: Bool = false) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(config.params(blackflowStartAvailable: supported)))
        as! [String: Any]
}
func rejects(_ config: RoguelikeConfiguration, supported: Bool = true) -> Bool {
    do {
        try config.validateBlackflowStart(available: supported)
        return false
    } catch { return true }
}
var config = RoguelikeConfiguration()
expect(config.blackflowStart == .init(), "Old defaults")
config.theme = .BlackFlow
config.mode = .blackflowStart
config.difficulty = .init(id: 6)
expect((try! params(config))["mode"] as? Int == 30003, "Mode")
for animal in RoguelikeConfiguration.BlackflowCultivation.allCases {
    config.blackflowStart.animals = [animal, animal]
    expect(rejects(config) == (animal == .swaddledFeatheredSerpent), "Duplicate animal semantics")
}
for animals: [RoguelikeConfiguration.BlackflowCultivation] in [
    [], [.swaddledCat], [.swaddledDog, .swaddledCat], [.swaddledCat, .swaddledCat, .swaddledCat],
] {
    config.blackflowStart.animals = animals
    expect(rejects(config) == (animals.count > 2), "Animal count")
}
config.blackflowStart.animals = []
for mask in 0...4095 {
    config.blackflowStart.rewards = mask
    expect(config.blackflowStart.effectiveRewards == mask & 63, "No serpent mask")
}
config.blackflowStart.animals = [.swaddledFeatheredSerpent]
for mask in 0...4095 {
    config.blackflowStart.rewards = mask
    expect(config.blackflowStart.effectiveRewards == mask, "Serpent mask")
}
for mask in [-1, 4096] {
    config.blackflowStart.rewards = mask
    expect(rejects(config), "Mask bounds")
}
config.blackflowStart.rewards = 0
config.blackflowStart.animals = []
config.blackflowStart.utopia = true
expect(rejects(config), "Empty priority")
config.blackflowStart.rewardPriority = [.pegasus, .pegasus]
expect(rejects(config), "Duplicate priority")
config.blackflowStart.rewardPriority = [.pegasus, .unnumberedItem]
expect(!rejects(config), "Serpent priority allowed without animal")
expect(rejects(config, supported: false), "Unknown Core fails closed")
config.blackflowStart.utopia = false
expect(!rejects(config, supported: false), "Turning Utopia off repairs unsupported-Core run")
config.blackflowStart.utopia = true
let supported = try params(config, supported: true)
expect(supported["blackflow_start_reward_priority"] as? [String] == ["pegasus", "unnumbered_item"], "Priority order")
expect((try! params(config))["blackflow_start_utopia"] == nil, "No unsupported phase2 parameter")
for level in [-1, 0, 5, 6, 15, Int(Int32.max)] {
    config.difficulty = .init(id: level)
    expect(rejects(config) == (level < 6 || level == Int(Int32.max)), "Explicit supported difficulty")
}
config.difficulty = .init(id: 6)
config.blackflowStart.preparationOperator = "机械师"
config.blackflowStart.preparationSquad = "特勤分队"
config.core_char = "目标干员"
config.roles = "取长补短"
config.squad = "后勤分队"
let utopia = try params(config, supported: true)
expect(utopia["core_char"] as? String == "目标干员", "Target opening")
expect(utopia["squad"] as? String == "后勤分队", "Target squad")
expect(utopia["collectible_mode_squad"] as? String == "特勤分队", "Preparation squad")
expect(
    (utopia["collectible_mode_core_char_list"] as? [[String: Any]])?.first?["name"] as? String == "机械师",
    "Preparation opening")
config.blackflowStart.preparationOperator = ""
config.use_support = true
config.use_nonfriend_support = true
let emptyPreparation = try params(config, supported: true)
expect(emptyPreparation["core_char"] as? String == "目标干员", "Target operator preserved with empty preparation")
expect(emptyPreparation["use_support"] as? Bool == true, "Target support preference preserved")
expect((emptyPreparation["collectible_mode_core_char_list"] as? [[String: Any]])?.isEmpty == true,
       "Empty preparation emits explicit list instead of inheriting target support")
config.blackflowStart.preparationOperator = "机械师"
config.blackflowStart.utopia = false
let phase1 = try params(config)
expect(phase1["core_char"] as? String == "机械师", "Phase1 preparation uses legacy opening keys")
expect(
    phase1["collectible_mode_squad"] as? String == "特勤分队" && phase1["squad"] as? String == "后勤分队",
    "Phase1 separate squads")
expect(config.core_char == "目标干员", "Stored opening unchanged")
for theme in RoguelikeConfiguration.Theme.allCases {
    for mode in theme.modes where !(theme == .BlackFlow && mode == .blackflowStart) {
        config.theme = theme
        config.mode = mode
        let json = try params(config, supported: true)
        expect(
            json.keys.filter {
                $0.hasPrefix("blackflow_start_") || $0 == "collectible_mode_roles"
                    || $0 == "collectible_mode_core_char_list"
            }.isEmpty, "Mode isolation")
    }
}
let encoded = try PropertyListEncoder().encode(config)
expect(try! PropertyListDecoder().decode(RoguelikeConfiguration.self, from: encoded) == config, "Persistence")
let partial = try JSONDecoder().decode(RoguelikeConfiguration.self, from: Data("{\"blackflowStart\":{}}".utf8))
expect(partial.blackflowStart == .init(), "Partial defaults")
if CommandLine.arguments.count == 4 {
    let core = URL(fileURLWithPath: CommandLine.arguments[1])
    let signed = URL(fileURLWithPath: CommandLine.arguments[2])
    let root = URL(fileURLWithPath: CommandLine.arguments[3])
    expect(
        try! BlackflowStartSupport.executableFingerprint(at: core) == BlackflowStartSupport.coreFingerprint,
        "Pinned dev Core")
    expect(
        try! BlackflowStartSupport.executableFingerprint(at: signed) == BlackflowStartSupport.coreFingerprint,
        "Fingerprint survives signing")
    expect(BlackflowStartSupport.matchesResources(at: root), "Pinned resources")
    if let ota = ProcessInfo.processInfo.environment["MAA_TEST_OTA_ROOT"] {
        expect(BlackflowStartSupport.permitsOverlay(at: URL(fileURLWithPath: ota)), "Reviewed live OTA overlay")
    }
}
let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: temp.appendingPathComponent("resource"), withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temp) }
expect(BlackflowStartSupport.permitsOverlay(at: temp), "Unrelated OTA")
try Data("{}".utf8).write(to: temp.appendingPathComponent("resource/tasks.json"))
expect(!BlackflowStartSupport.permitsOverlay(at: temp), "Legacy task override rejects")
print("PASS \(checks) BlackFlow start checks")
