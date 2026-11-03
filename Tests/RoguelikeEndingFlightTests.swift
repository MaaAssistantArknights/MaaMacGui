import Foundation

var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    precondition(condition(), message)
}
func params(_ config: RoguelikeConfiguration) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(config.params)) as! [String: Any]
}
let old = try JSONDecoder().decode(RoguelikeConfiguration.self, from: Data("{}".utf8))
expect(old.blackflowEnding == .coreDefault && !old.blackflowFastFlight, "Old defaults")
var config = old
config.theme = .BlackFlow
config.mode = .exp
config.squad = "后勤分队"
config.roles = "取长补短"
config.core_char = "用户干员"
config.use_support = true
config.use_nonfriend_support = true
expect(try! params(config)["blackflow_strategy"] == nil, "Migration must preserve inferred Core strategy")
for ending in RoguelikeConfiguration.BlackflowEnding.allCases {
    config.blackflowEnding = ending
    let value = try params(config)["blackflow_strategy"] as? String
    expect(value == (ending == .coreDefault ? nil : ending.rawValue), "Ending parameter")
}
let saved = config
config.blackflowFastFlight = true
let flight = try params(config)
expect(flight["squad"] as? String == "特勤分队", "Flight squad")
expect(flight["roles"] as? String == "稳扎稳打", "Flight roles")
expect(flight["core_char"] as? String == "机械师", "Flight operator")
expect(flight["use_support"] as? Bool == false, "Flight support")
expect(flight["use_nonfriend_support"] == nil, "No nonfriend support during flight")
expect(flight["blackflow_strategy"] == nil && flight["fast_flight"] == nil, "Use Core inferred flight strategy")
expect(config.squad == saved.squad && config.roles == saved.roles && config.core_char == saved.core_char && config.use_support, "Stored opening preserved")
config.blackflowFastFlight = false
expect(try! params(config)["core_char"] as? String == "用户干员", "Opening restored")
for theme in RoguelikeConfiguration.Theme.allCases {
    for mode in theme.modes {
        config.theme = theme
        config.mode = mode
        config.blackflowEnding = .ending2
        config.blackflowFastFlight = true
        let json = try params(config)
        let strategy = json["blackflow_strategy"] as? String
        expect(strategy == (theme == .BlackFlow && mode == .babyAnimal ? "baby_animal" : nil), "Theme/mode strategy leak")
        expect(config.usesBlackflowFastFlight == (theme == .BlackFlow && mode == .exp), "Flight predicate")
    }
}
let encoded = try JSONEncoder().encode(config)
expect(try! JSONDecoder().decode(RoguelikeConfiguration.self, from: encoded) == config, "JSON roundtrip")
let plist = try PropertyListEncoder().encode(config)
expect(try! PropertyListDecoder().decode(RoguelikeConfiguration.self, from: plist) == config, "Plist roundtrip")
for key in ["blackflowEnding", "blackflowFastFlight"] {
    var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
    object[key] = ["invalid"]
    do {
        _ = try JSONDecoder().decode(RoguelikeConfiguration.self, from: JSONSerialization.data(withJSONObject: object))
        preconditionFailure("Malformed field must reject: \(key)")
    } catch { checks += 1 }
}
print("PASS \(checks) ending/flight checks")
