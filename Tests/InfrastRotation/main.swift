import Foundation

var assertions = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    assertions += 1
    if !value() { fatalError("FAIL: \(message)") }
}
func run(index: Int = 0, count: Int = 2, duration: Double? = 1440,
         fingerprint: String = "original", connection: String = "game") -> InfrastRotationRun {
    .init(id: UUID(), profile: "Default", connection: connection, filename: "plan.json",
          fingerprint: fingerprint, index: index, count: count, name: "班 \(index)",
          durationMinutes: duration, automatic: true, selectedIndex: index, descriptionPost: nil)
}
struct Fixture: Decodable {
    let name: String; let count: Int; let last: Int; let duration: Double; let next: Int; let seconds: Double
}
let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
let anchor = Date(timeIntervalSince1970: 1_800_000_000)
for f in fixtures {
    var state = InfrastRotation(automatic: true)
    let attempt = run(index: f.last, count: f.count, duration: f.duration)
    state.complete(attempt, at: anchor)
    check(state.nextIndex(fingerprint: "original", count: f.count, fallback: 0, connection: "game") == f.next, f.name)
    check(state.suggestedDate(fingerprint: "original") == anchor.addingTimeInterval(f.seconds), f.name + " time")
    let snapshot = state
    state.complete(attempt, at: anchor.addingTimeInterval(1000))
    check(state == snapshot, "duplicate completion is idempotent")
}
var state = InfrastRotation(automatic: true)
check(state.nextIndex(fingerprint: "original", count: 6, fallback: 4) == 4, "initial selection")
check(state.nextIndex(fingerprint: "original", count: 6, fallback: -1) == 0, "invalid initial")
check(state.nextIndex(fingerprint: "original", count: 0, fallback: 0) == nil, "empty plans")
check(state.suggestedDate(fingerprint: "original") == nil, "no fabricated history")
state.complete(run(), at: anchor)
check(state.nextIndex(fingerprint: "changed", count: 2, fallback: 0) == 0, "changed file")
check(state.suggestedDate(fingerprint: "changed") == nil, "changed file time invalid")
check(state.nextIndex(fingerprint: "original", count: 2, fallback: 0, connection: "other") == 0, "other connection")
check(state.suggestedDate(fingerprint: "original", connection: "other") == nil, "other connection time")
state.automatic = false
check(state.nextIndex(fingerprint: "original", count: 2, fallback: 0) == 0, "manual selection not overridden")
state.intervalMinutes = 720
check(state.suggestedDate(fingerprint: "original") == anchor.addingTimeInterval(43200), "uniform interval")
state.intervalMinutes = nil
state.complete(run(index: 1, duration: 480), at: anchor.addingTimeInterval(3 * 86400 + 9000))
check(state.suggestedDate(fingerprint: "original") == anchor.addingTimeInterval(3 * 86400 + 9000 + 28800), "late execution reanchors")
state.complete(run(duration: 960), at: anchor.addingTimeInterval(3600))
check(state.suggestedDate(fingerprint: "original") == anchor.addingTimeInterval(3600 + 57600), "early execution reanchors")
for invalid: Double? in [nil, 0, -1, .infinity, .nan, Double.greatestFiniteMagnitude] {
    check(InfrastRotation.validMinutes(invalid) == nil, "invalid duration")
}
for raw in ["null", "0", "-1", "\"1440\"", "1e200"] {
    let plan = try JSONDecoder().decode(MAAInfrast.self, from: Data("{\"plans\":[{\"name\":\"A\",\"duration\":\(raw)}]}".utf8))
    check(plan.plans[0].duration == nil, "invalid optional hint doesn't reject plan")
}
let legacy = InfrastConfiguration()
check(legacy.rotation == nil, "old config doesn't enable automatic")
var config = legacy
config.rotation = state
config.plan_index = 1
let data = try PropertyListEncoder().encode(config)
let restored = try PropertyListDecoder().decode(InfrastConfiguration.self, from: data)
check(restored == config, "plist round trip")
let coreData = try JSONEncoder().encode(config.params)
let core = try JSONSerialization.jsonObject(with: coreData) as! [String: Any]
check(core["rotation"] == nil, "GUI history never sent to core")
check(core["plan_index"] as? Int == 1, "core gets concrete index")
let baseData = try JSONEncoder().encode(legacy.params)
var metadataFree = try JSONSerialization.jsonObject(with: coreData) as! [String: Any]
metadataFree["plan_index"] = 0
let baseObject = try JSONSerialization.jsonObject(with: baseData) as! [AnyHashable: Any]
check(NSDictionary(dictionary: metadataFree).isEqual(to: baseObject), "all original Core parameters retained")
check(InfrastRotationRun.fingerprint(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "portable SHA256")
print("PASS: \(assertions) assertions, \(fixtures.count) shared fixtures")
