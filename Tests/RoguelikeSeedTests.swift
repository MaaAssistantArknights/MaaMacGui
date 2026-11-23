import Foundation
var checks = 0
func expect(_ value: @autoclosure () -> Bool, _ message: String) { checks += 1; precondition(value(), message) }
func params(_ config: RoguelikeConfiguration, input: Bool) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(config.params(supportsSeedInput: input))) as! [String: Any]
}
var config = RoguelikeConfiguration()
expect(!config.seedEnabled && config.seed.isEmpty, "Migration disabled")
for seed in ["2b3c4d,rogue_1,120", "a0,rogue_0,0"] {
    expect(RoguelikeConfiguration.isValidSeed(seed), "Valid seed format accepted")
}
for seed in ["aBcD1234", "2b3c4d, rogue_1, 120", "2b3c4d,rogue_1", "2b3c4d,rogue_1,120,extra", "2b3c4d,ROGUE_1,120", "，rogue_1,1"] {
    expect(!RoguelikeConfiguration.isValidSeed(seed), "Invalid seed format rejected")
}
for theme in RoguelikeConfiguration.Theme.allCases {
 for mode in theme.modes {
  for squad in theme.squads {
   config.theme = theme; config.mode = mode; config.squad = squad
   config.seedEnabled = true; config.seed = "  2b3c4d,rogue_1,120\n"
   for input in [true, false] {
    let expected = input && theme == .Sarkaz && mode == .investment && ["点刺成锭分队", "后勤分队"].contains(squad)
    expect((try! params(config, input: input))["start_with_seed"] as? String == (expected ? "2b3c4d,rogue_1,120" : nil), "Applicability matrix")
    expect(config.seed == "  2b3c4d,rogue_1,120\n" && config.seedEnabled, "Preferences preserved")
   }
  }
 }
}
config.theme = .Sarkaz; config.mode = .investment; config.squad = "后勤分队"
for text in ["", "  \n\t"] { config.seed = text; expect((try! params(config, input: true))["start_with_seed"] == nil, "Empty seed omitted") }
for text in ["aBcD1234", "2b3c4d, rogue_1, 120"] { config.seed = text; expect((try! params(config, input: true))["start_with_seed"] == nil, "Malformed seed omitted") }
config.seed = "2b3c4d,rogue_1,120"; config.seedEnabled = false
expect((try! params(config, input: true))["start_with_seed"] == nil, "Disabled seed omitted")
config.seedEnabled = true
expect((try! params(config, input: false))["start_with_seed"] == nil, "Enabled seed omitted without transport")
expect((try! JSONSerialization.jsonObject(with: JSONEncoder().encode(config.params)) as! [String: Any])["start_with_seed"] == nil, "Unknown transport fails closed")
let data = try PropertyListEncoder().encode(config)
expect(try! PropertyListDecoder().decode(RoguelikeConfiguration.self, from: data) == config, "Persistence")
print("PASS \(checks) seed checks")
