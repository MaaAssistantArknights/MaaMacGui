import Foundation

private var checks = 0
private func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    precondition(value(), message)
}

// The script prepends the production @JSONRepresentable settlement type verbatim.
private func decode(_ packet: [String: Any]) throws -> RoguelikeSettlementDetails {
    let data = try JSONSerialization.data(withJSONObject: packet)
    return try RoguelikeSettlementDetails(json: JSON(data))
}

private func render(_ packet: RoguelikeSettlementDetails, format: String) -> String {
    String(format: format, arguments: [
        packet.game_pass ? "✓" : "✗", packet.floorDescription, packet.step ?? 0,
        packet.combat ?? 0, packet.emergency ?? 0, packet.boss ?? 0,
        packet.recruit ?? 0, packet.collection ?? 0,
        packet.difficulty ?? 0, packet.score ?? 0, packet.exp ?? "", packet.skill ?? "",
    ])
}

let fixturesURL = URL(fileURLWithPath: CommandLine.arguments[1])
let catalogURL = URL(fileURLWithPath: CommandLine.arguments[2])
let packets = try JSONSerialization.jsonObject(with: Data(contentsOf: fixturesURL)) as! [[String: Any]]
let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as! [String: Any]
let strings = catalog["strings"] as! [String: Any]
let settlement = strings["RoguelikeSettlement"] as! [String: Any]
let localizations = settlement["localizations"] as! [String: Any]
let chinese = localizations["zh-Hans"] as! [String: Any]
let unit = chinese["stringUnit"] as! [String: String]
// Xcode's catalog named substitutions compile to normal positional printf specifiers.
let sourceFormat = unit["value"]!
expect(sourceFormat.contains("%2$(floor)@"), "Floor substitution must accept unknown text")
let format = sourceFormat.replacingOccurrences(of: #"\$\([^)]*\)"#, with: "$", options: .regularExpression)
let expected = [
    "肉鸽结算：✗ (难度0)\n探索：?层2步\n战斗：1 / 0紧急 / 0 BOSS\n招募：2 收藏品：4\n得分：36 经验：MAX 点数：MAX",
    "肉鸽结算：✗ (难度0)\n探索：?层2步\n战斗：0 / 0紧急 / 0 BOSS\n招募：6 收藏品：5\n得分：119 经验：MAX 点数：MAX",
]
expect(packets.count == expected.count, "Both captured settlement packets are covered")
for (index, envelope) in packets.enumerated() {
    let details = envelope["details"] as! [String: Any]
    expect(details["floor"] == nil, "Captured packet actually omits floor")
    let parsed = try decode(details)
    expect(parsed.floor == nil, "Production JBird decoder keeps missing floor nil")
    expect(parsed.floorDescription == "?", "Missing floor displays unknown")
    expect(render(parsed, format: format) == expected[index], "Captured packet rendering preserves all other statistics")
}
var details = packets[0]["details"] as! [String: Any]
for floor in [0, 2] {
    details["floor"] = floor
    let parsed = try decode(details)
    expect(parsed.floor == floor, "Explicit floor preserved")
    expect(parsed.floorDescription == String(floor), "Explicit zero is not unknown")
    expect(render(parsed, format: format).contains("探索：\(floor)层2步"), "Explicit floor rendered correctly")
}
details["floor"] = NSNull()
private let null = try decode(details)
expect(null.floor == nil && null.floorDescription == "?", "JSON null is unknown")
print("PASS \(checks) captured settlement/parser/format checks")
