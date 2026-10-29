import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    precondition(condition(), message)
}

let encoder = JSONEncoder()
let decoder = JSONDecoder()
var names = Set<String>()
for ending in SecretFrontConfiguration.Ending.allCases {
    for event in SecretFrontConfiguration.Event.allCases {
        let configuration = SecretFrontConfiguration(ending: ending, event: event)
        let expected =
            "MiniGame@SecretFront@Begin@Ending" + ending.rawValue
            + (event == .unspecified ? "" : "@" + event.rawValue)
        check(configuration.taskName == expected, "exact protocol name")
        check(!configuration.taskName.hasSuffix("@"), "no empty suffix")
        check(configuration.params == ["task_names": [expected]], "exact payload")
        let restored = try decoder.decode(SecretFrontConfiguration.self, from: encoder.encode(configuration))
        check(restored == configuration, "persisted values round trip")
        names.insert(configuration.taskName)
    }
}
check(names.count == 20, "20 distinct combinations")
for invalid in ["Z", "a", "", "A@EndingE"] {
    let data = try JSONSerialization.data(withJSONObject: ["ending": invalid, "event": ""])
    check((try? decoder.decode(SecretFrontConfiguration.self, from: data)) == nil, "reject invalid ending")
}
let invalidEvent = try JSONSerialization.data(withJSONObject: ["ending": "A", "event": "@游侠"])
check((try? decoder.decode(SecretFrontConfiguration.self, from: invalidEvent)) == nil, "reject invalid event")

var run = SecretFrontRun()
run.begin(taskID: 7, configuration: .init(ending: .C, event: .phantom))
run.observe(taskID: 8, task: "MiniGame@SecretFront@SelectTeam")
run.observe(taskID: 7, task: "MiniGame@PixelPaint@SelectTeam")
check(run.lastStep == nil, "ignore other task IDs and prefixes")
run.observe(taskID: 7, task: "MiniGame@SecretFront@SelectTeam")
let first = run.lastStep
check(first != nil, "accept owned step")
let count = run.messages.count
run.observe(taskID: 7, task: "MiniGame@SecretFront@SelectTeam")
run.observe(taskID: 7, task: "MiniGame@SecretFront@Unknown")
check(run.messages.count == count && run.lastStep == first, "deduplicate and retain last valid step")
run.observe(taskID: 7, task: "MiniGame@SecretFront@PreClickDetect", candidate: "游侠")
check(run.lastStep?.contains("游侠") == true, "candidate belongs to this run")
run.finish(taskID: 8, result: .failed)
check(run.taskID == 7, "foreign terminal callback ignored")
run.finish(taskID: 7, result: .failed)
check(run.taskID == nil && run.lastStep != nil, "failure releases ownership and preserves diagnosis")
let failed = run
run.observe(taskID: 7, task: "MiniGame@SecretFront@End")
check(run == failed, "late callback ignored")
for result in [SecretFrontRun.Result.completed, .stopped, .failed] {
    run.begin(taskID: 9, configuration: .init())
    check(run.lastStep == nil && run.messages.count == 1, "new run clears old state")
    run.observe(taskID: 7, task: "MiniGame@SecretFront@End")
    check(run.lastStep == nil, "old run cannot contaminate new run")
    run.finish(taskID: 9, result: result)
    check(run.taskID == nil, "terminal result releases ID")
}
run.begin(taskID: 10, configuration: .init())
run.release()
run.observe(taskID: 10, task: "MiniGame@SecretFront@End")
check(run.lastStep == nil, "reset releases ownership")
run.begin(taskID: 11, configuration: .init())
for index in 0..<250 {
    run.observe(taskID: 11, task: "MiniGame@SecretFront@PreClickDetect", candidate: "event-\(index)")
}
check(run.messages.count == 200, "log bounded")

let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
check(!SecretFrontConfiguration.hasResources(in: directory), "missing resources unavailable")
var definitions: [String: [String: String]] = [:]
for key in ["Begin", "Run", "SelectTeam", "Actions", "End"] { definitions["MiniGame@SecretFront@" + key] = [:] }
try JSONSerialization.data(withJSONObject: definitions).write(to: directory.appendingPathComponent("tasks.json"))
check(!SecretFrontConfiguration.hasResources(in: directory), "missing templates unavailable")
let templates = directory.appendingPathComponent("template/MiniGame/SecretFront")
try FileManager.default.createDirectory(at: templates, withIntermediateDirectories: true)
for name in ["SelectTeam", "TeamManagement", "TeamIntelligence", "TeamMedicine"] {
    try Data().write(to: templates.appendingPathComponent("MiniGame@SecretFront@" + name + ".png"))
}
check(SecretFrontConfiguration.hasResources(in: directory), "monolithic resources recognized")
try Data("corrupt".utf8).write(to: directory.appendingPathComponent("tasks.json"))
check(!SecretFrontConfiguration.hasResources(in: directory), "corrupt resources unavailable")
try FileManager.default.createDirectory(
    at: directory.appendingPathComponent("tasks/MiniGame"), withIntermediateDirectories: true)
try JSONSerialization.data(withJSONObject: definitions).write(
    to: directory.appendingPathComponent("tasks/MiniGame/SecretFront.json"))
check(SecretFrontConfiguration.hasResources(in: directory), "split resources recognized")
if CommandLine.arguments.count > 1 {
    check(
        SecretFrontConfiguration.hasResources(in: URL(fileURLWithPath: CommandLine.arguments[1])),
        "current resource tree available")
}
print("SecretFront: \(checks) checks passed")
