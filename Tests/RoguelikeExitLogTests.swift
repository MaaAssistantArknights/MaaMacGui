import Foundation

private var checks = 0
private func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    precondition(value(), message)
}

private enum LogResource: String {
    case explorationExiting = "ExplorationExiting"
    case explorationAbandoned = "ExplorationAbandoned"
}
private var entries: [(severity: String, resource: LogResource)] = []
private func logInfo(_ resource: LogResource) { entries.append(("info", resource)) }
private func logWarn(_ resource: LogResource) { entries.append(("warning", resource)) }

// The script prepends the real JBird ProcessTaskDetails type and exact exit case.
let packets = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [[String: Any]]
let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))) as! [String: Any]
expect(packets.count == 2, "Both captured exit/limit packets are covered")
for packet in packets {
    let data = packet["data"] as! [String: Any]
    let details = data["details"] as! [String: Any]
    let parsed = try ProcessTaskDetails(json: JSON(JSONSerialization.data(withJSONObject: details)))
    expect(data["subtask"] as? String == "ProcessTask", "Actual process callback")
    if packet["event"] as? String == "SubTaskStart" {
        expect(parsed.task == "ExitThenAbandon", "Exit callback precedes the click")
        expect(details["action"] as? String == "ClickSelf", "Captured task is the map exit")
        handleExit(parsed)
    } else {
        expect(data["what"] as? String == "ExceededLimit" && parsed.task == "Abandon", "Captured abandon task was skipped")
        expect(parsed.exec_times == 0 && details["max_times"] as? Int == 0, "No abandon action executed")
    }
}
expect(entries.count == 1, "Only the start callback logs an exit")
expect(entries[0].severity == "info", "Returning from the map is informational")
expect(entries[0].resource == .explorationExiting, "Exiting does not claim abandonment or saved progress")
let strings = catalog["strings"] as! [String: Any]
let message = strings[entries[0].resource.rawValue] as! [String: Any]
let localizations = message["localizations"] as! [String: Any]
for (locale, expected) in ["zh-Hans": "正在退出探索", "en": "Exiting exploration", "ko": "탐험에서 나가는 중"] {
    let value = localizations[locale] as! [String: Any]
    let unit = value["stringUnit"] as! [String: String]
    expect(unit["value"] == expected, "Start-event wording stays neutral in \(locale)")
}
print("PASS \(checks) captured retained-run exit/parser/log checks")
