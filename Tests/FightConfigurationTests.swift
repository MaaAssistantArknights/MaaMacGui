import Foundation

// Compile the production model without launching the app or linking MaaCore.
typealias MAATaskConfiguration = Codable & Hashable & Sendable

enum MAATaskType: String {
    case Fight
    var description: String { rawValue }
}

enum MAATask {
    case fight(FightConfiguration)
}

@main
struct FightConfigurationTests {
    static func main() throws {
        let cases: [(String, String)] = [
            ("AP-5", "AP-5"), ("ap-5", "AP-5"), ("Ap-5", "AP-5"), ("aP-5", "AP-5"),
            (" \tAp-5\r\n", "AP-5"), ("yw-8", "YW-8"), ("Yw-8", "YW-8"),
            ("pr-a-1", "PR-A-1"), ("Pr-a-1", "PR-A-1"), ("pR-A-1", "PR-A-1"),
            ("jt8-2", "JT8-2"), ("Jt8-2", "JT8-2"), ("s3-1", "S3-1"), ("1-7", "1-7"),
            ("Annihilation", "Annihilation"), ("annihilation", "Annihilation"),
            (" ANNIHILATION ", "Annihilation"), ("aNnIhIlAtIoN", "Annihilation"),
            ("AveMujica-8", "AveMujica-8"), (" AveMujica-8 ", "AveMujica-8"),
            ("GTToGT-5", "GTToGT-5"), ("CustomStage-1", "CustomStage-1"),
            ("avemujica-8", "avemujica-8"), ("customstage-1", "customstage-1"),
            ("H10-1-Hard", "H10-1-Hard"), ("15-1-Normal", "15-1-Normal"),
            ("h10-1-hard", "h10-1-hard"),  // The core handles main-story difficulty suffixes.
            ("", ""), (" \n\t", ""), ("未知关卡", "未知关卡"), ("ＡＰ-5", "ＡＰ-5"),
            ("AP -5", "AP -5"),
            ("OF-F3", "OF-F3"), ("of-f3", "OF-F3"), ("Of-F3", "OF-F3"),
        ]
        var failures = [String]()
        for (input, expected) in cases {
            let normalized = FightConfiguration.normalizedStage(input)
            if normalized != expected {
                failures.append(
                    "normalize \(input.debugDescription): \(normalized.debugDescription) != \(expected.debugDescription)"
                )
            }
            if FightConfiguration.normalizedStage(normalized) != normalized {
                failures.append("not idempotent: \(input.debugDescription)")
            }

            let fixture: [String: Any] = [
                "stage": input, "medicine": 3, "medicine_expire_days": 2, "stone": 1,
                "times": 4, "series": 6, "drops": ["30012": 7], "report_to_penguin": true,
                "penguin_id": "test", "server": "CN", "client_type": "Official", "DrGrandet": true,
            ]
            let config = try JSONDecoder().decode(
                FightConfiguration.self, from: JSONSerialization.data(withJSONObject: fixture))
            let encoded = try JSONEncoder().encode(config.params)
            let payload = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
            var expectedPayload = fixture
            expectedPayload["stage"] = expected
            if !NSDictionary(dictionary: payload).isEqual(to: expectedPayload) {
                failures.append("unexpected payload: \(input.debugDescription)")
            }
            if config.stage != input {
                failures.append("params mutated the stored config: \(input.debugDescription)")
            }
            let persisted = try PropertyListEncoder().encode(config.params)
            let restored = try PropertyListDecoder().decode(FightConfiguration.self, from: persisted)
            if restored.stage != expected {
                failures.append("persistence round trip: \(input.debugDescription)")
            }
        }
        for failure in failures { print("FAIL: \(failure)") }
        guard failures.isEmpty else { exit(1) }
        print(
            "PASS: \(cases.count) stage cases; normalization, idempotence, payload fields, value semantics and plist round trips"
        )
    }
}
