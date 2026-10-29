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

// These are external callback envelopes, after AbstractTask::callback strips
// the ProcessTask namespace. Keep the wire shape distinct from source task names.
struct RawStepCallback: Decodable {
    let message: Int
    let details: Envelope
    struct Envelope: Decodable {
        let taskid: Int32
        let subtask: String
        let details: Step
    }
    struct Step: Decodable {
        let task: String
        let result: Result?
    }
    struct Result: Decodable { let text: String? }
}
let wireCallbacks = #"""
    [
        {"message":20001,"details":{"taskid":41,"subtask":"ProcessTask","taskchain":"Custom","details":{"task":"SelectTeam","exec_times":1,"result":{}}}},
        {"message":20001,"details":{"taskid":41,"subtask":"ProcessTask","taskchain":"Custom","details":{"task":"Management","exec_times":1,"result":{}}}},
        {"message":20001,"details":{"taskid":41,"subtask":"ProcessTask","taskchain":"Custom","details":{"task":"PreClickDetect","exec_times":1,"result":{"text":"游侠"}}}}
    ]
    """#.data(using: .utf8)!
let callbacks = try decoder.decode([RawStepCallback].self, from: wireCallbacks)
var wireRun = SecretFrontRun()
wireRun.begin(taskID: 41, configuration: .init())
for callback in callbacks {
    check(callback.message == 20001 && callback.details.subtask == "ProcessTask", "production step callback shape")
    wireRun.observe(
        taskID: callback.details.taskid, task: callback.details.details.task,
        candidate: callback.details.details.result?.text)
    check(wireRun.lastStep != nil, "owned bare wire step is observed")
}
check(wireRun.messages.count == 4, "all three production wire steps are logged")
check(wireRun.lastStep?.contains("游侠") == true, "wire candidate text retained")
let observedWireRun = wireRun
for task in ["MiniGame@PixelPaint@SelectTeam", "Other@Management", "Other@MiniGame@SecretFront@End", "Unknown", ""] {
    wireRun.observe(taskID: 41, task: task)
    check(wireRun == observedWireRun, "foreign qualified or unknown wire step rejected")
}
wireRun.observe(taskID: 42, task: "EventContinue")
check(wireRun == observedWireRun, "bare step with foreign task ID rejected")
wireRun.finish(taskID: 41, result: .failed)
let terminatedWireRun = wireRun
check(terminatedWireRun.lastStep?.contains("游侠") == true, "wire last step survives failure")
wireRun.observe(taskID: 41, task: "End")
check(wireRun == terminatedWireRun, "late bare callback ignored after failure")

for step in [
    "SelectTeam", "Intelligence", "Management", "Medicine", "SelectTeamOK", "RouteSelect",
    "PreClickDetect", "Actions", "ContinueResult", "ActionContinue", "EventContinue", "EventDetected", "End",
] {
    var bareRun = SecretFrontRun()
    var qualifiedRun = SecretFrontRun()
    bareRun.begin(taskID: 51, configuration: .init())
    qualifiedRun.begin(taskID: 51, configuration: .init())
    bareRun.observe(taskID: 51, task: step)
    qualifiedRun.observe(taskID: 51, task: "MiniGame@SecretFront@" + step)
    check(bareRun.lastStep != nil, "whitelisted bare step recognized")
    check(bareRun == qualifiedRun, "wire suffix and source task name describe the same observed step")
}
var boundedWireRun = SecretFrontRun()
boundedWireRun.begin(taskID: 61, configuration: .init())
for index in 0..<250 {
    boundedWireRun.observe(taskID: 61, task: "PreClickDetect", candidate: "wire-event-\(index)")
}
check(boundedWireRun.messages.count == 200, "production wire logs stay bounded")
check(boundedWireRun.lastStep?.contains("wire-event-249") == true, "bounded wire log preserves last step")

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
