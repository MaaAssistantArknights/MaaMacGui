import Foundation

var count = 0
func check(_ condition: Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    precondition(condition, message, file: file, line: line)
    count += 1
}
func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
func activities(_ groups: [String: Any]?) throws -> MAAStageActivity {
    var json: [String: Any] = ["miniGame": []]
    json["sideStoryStage"] = groups
    return try JSONDecoder().decode(MAAStageActivity.self, from: JSONSerialization.data(withJSONObject: json))
}
func group(start: String = "2026/10/22 04:00:00", end: String = "2026/10/26 03:59:59", zone: Double = 8) -> [String:
    Any]
{
    ["Activity": ["UtcStartTime": start, "UtcExpireTime": end, "TimeZone": zone], "Stages": [["Value": "TEST-1"]]]
}
func window(_ data: MAAStageActivity?, at now: Date, channel: MAAClientChannel = .Official, enabled: Bool = true)
    -> StageActivityContext.MedicineWindow
{
    StageActivityContext(channel: channel, activities: data).medicineWindow(at: now, enabled: enabled)
}
let end = date("2026-10-25T19:59:59Z")
let activity = try activities(["one": group()])
check(window(activity, at: end.addingTimeInterval(-48 * 3600 - 1)) == .inactive, "48h + 1s")
check(window(activity, at: end.addingTimeInterval(-48 * 3600)) == .inactive, "strict 48h")
check(window(activity, at: end.addingTimeInterval(-48 * 3600 + 1)) == .extended(days: 2), "48h - 1s")
check(window(activity, at: end) == .inactive, "end exclusive")
check(window(activity, at: end.addingTimeInterval(1)) == .inactive)
check(window(activity, at: date("2026-10-21T19:59:59Z")) == .inactive, "not started")
let short = try activities(["one": group(start: "2026/10/25 04:00:00", end: "2026/10/26 04:00:00")])
check(window(short, at: date("2026-10-24T20:00:00Z")) == .extended(days: 1), "start inclusive")
check(window(nil, at: end) == .unavailable)
check(window(try activities(nil), at: end) == .unavailable)
check(window(try activities([:]), at: end) == .inactive)
check(window(nil, at: end, enabled: false) == .inactive)
for bad in [
    group(start: "not-a-date"), group(end: "2026/02/30 04:00:00"), group(start: "2026/10/27 04:00:00"),
    group(zone: 100),
] {
    check(window(try activities(["bad": bad]), at: end) == .unavailable)
    check(window(try activities(["valid": group(), "bad": bad]), at: end.addingTimeInterval(-1)) == .extended(days: 1))
}
check(window(try activities(["bad": ["Activity": "broken"]]), at: end) == .unavailable)
check(window(try activities(["valid": group(), "bad": ["Activity": "broken"]]), at: end.addingTimeInterval(-1)) == .unavailable, "undecodable peer nulls the payload")
let overlap = try activities(["later": group(end: "2026/11/01 04:00:00"), "earlier": group()])
check(window(overlap, at: end.addingTimeInterval(-1)) == .extended(days: 1), "nearest active end")
let reversed = try activities(["earlier": group(), "later": group(end: "2026/11/01 04:00:00")])
check(window(overlap, at: end.addingTimeInterval(-1)) == window(reversed, at: end.addingTimeInterval(-1)))
check(window(try activities(["valid": group(), "bad": [:]]), at: end.addingTimeInterval(-1)) == .extended(days: 1), "partial malformed keeps valid group")
check(window(try activities(["valid": group(), "bad": [:]]), at: end.addingTimeInterval(48 * 3600)) == .inactive)
check(window(try activities(["bad": group(start: "not-a-date"), "worse": [:]]), at: end) == .unavailable, "all groups malformed")
for channel in MAAClientChannel.allCases {
    let offset = channel == .YoStarEN ? -7 : ([MAAClientChannel.YoStarJP, .YoStarKR].contains(channel) ? 9 : 8)
    // Local Sunday/Monday boundaries, independent of the host timezone.
    let utcSunday = date("2026-10-25T00:00:00Z").addingTimeInterval(Double(-offset * 3600))
    for (seconds, days) in [(4 * 3600 - 1, 2), (4 * 3600, 1), (28 * 3600 - 1, 1), (28 * 3600, 7)] {
        check(
            channel.calendar.medicineExpiryDaysUntilWeekEnd(at: utcSunday.addingTimeInterval(Double(seconds))) == days,
            "server week boundary")
    }
    for weekday in 0..<7 {
        let now = utcSunday.addingTimeInterval(Double(weekday * 86400 + 4 * 3600))
        check(channel.calendar.medicineExpiryDaysUntilWeekEnd(at: now) == (weekday == 0 ? 1 : 8 - weekday))
    }
}
check(MAAClientChannel.Bilibili.stageActivityKey == "Official")
for channel in MAAClientChannel.allCases where channel != .Bilibili {
    check(channel.stageActivityKey == channel.rawValue)
}
let defaults = FightConfiguration()
check(!defaults.useActivityMedicine && defaults.medicine_expire_days == 0)
for baseDays in [0, 1, 2, 7, 10] {
    for enabled in [false, true] {
        var config = defaults
        config.useActivityMedicine = enabled
        config.medicine_expire_days = baseDays
        config.medicine = 3
        config.stone = 0
        config.times = 5
        config.series = 2
        config.drops = ["30013": 4]
        let snapshot = config
        let context = StageActivityContext(channel: .Official, activities: activity)
        let params = config.params(at: end.addingTimeInterval(-47 * 3600), stageActivity: context)
        check(params.medicine_expire_days == (enabled ? max(baseDays, 2) : baseDays))
        check(config == snapshot, "projection cannot write derived values to preferences")
        let original = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config.params)) as! [String: Any]
        let effective = try JSONSerialization.jsonObject(with: JSONEncoder().encode(params)) as! [String: Any]
        check(original["useActivityMedicine"] == nil)
        check(
            effective.filter { $0.key != "medicine_expire_days" } as NSDictionary == original.filter {
                $0.key != "medicine_expire_days"
            } as NSDictionary)
        check(config.params(at: end, stageActivity: context).medicine_expire_days == baseDays)
        check(
            config.params(at: end.addingTimeInterval(-1), stageActivity: .init(channel: .Official, activities: nil))
                .medicine_expire_days == baseDays)
        try check(
            PropertyListDecoder().decode(FightConfiguration.self, from: PropertyListEncoder().encode(config)) == config)
        try check(JSONDecoder().decode(FightConfiguration.self, from: JSONEncoder().encode(config)) == config)
    }
}
for old in ["{}", "{\"expiring_medicine\": 1}", "{\"medicine_expire_days\": 7}"] {
    let config = try JSONDecoder().decode(FightConfiguration.self, from: Data(old.utf8))
    check(!config.useActivityMedicine)
    check(config.medicine_expire_days == (old.contains("expiring_medicine") ? 2 : (old.contains("7") ? 7 : 0)))
}
let legacyJSON = """
    {"enable":true,"stage":"1-7","medicine":5,"expiring_medicine":1,"stone":0,"times":1,"series":0,"report_to_penguin":false,"penguin_id":"","server":"CN","client_type":"","DrGrandet":false}
    """
let migrated = FightConfiguration(
    migrating: try JSONDecoder().decode(LegacyFightConfiguration.self, from: Data(legacyJSON.utf8)))
check(
    !migrated.useActivityMedicine && migrated.medicine_expire_days == 2 && migrated.medicine == 5 && migrated.times == 1
)
if let path = CommandLine.arguments.dropFirst().first {
    let servers = try JSONDecoder().decode(
        [String: MAAStageActivity].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    check(servers.count == 5)
    for entry in servers.values {
        check(entry.sideStoryStage != nil)
        for group in entry.sideStoryStage?.values ?? [:].values {
            check(group.Activity?.interval != nil)
        }
    }
}
print("PASS: \(count) activity/48h/week/server/migration/JSON/plist/projection checks")
