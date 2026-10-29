// Secret Front entry and callback scope adapted from A1yssa8's proposal in
// https://github.com/MaaAssistantArknights/MaaMacGui/issues/130.
import Foundation

struct SecretFrontConfiguration: Codable, Equatable {
    enum Ending: String, CaseIterable, Codable { case A, B, C, D, E }
    enum Event: String, CaseIterable, Codable {
        case unspecified = ""
        case support = "支援作战平台"
        case ranger = "游侠"
        case phantom = "诡影迷踪"
    }

    var ending: Ending = .A
    var event: Event = .unspecified

    var taskName: String {
        let entry = "MiniGame@SecretFront@Begin@Ending" + ending.rawValue
        return event == .unspecified ? entry : entry + "@" + event.rawValue
    }

    var params: [String: [String]] { ["task_names": [taskName]] }
}

/// A run owns only callbacks carrying its exact Core task ID. Completion retains
/// the last observed step for diagnosis, but releases callback ownership.
struct SecretFrontRun: Equatable {
    enum Result { case completed, stopped, failed }

    private(set) var taskID: Int32?
    private(set) var lastStep: String?
    private(set) var messages: [String] = []

    mutating func begin(taskID: Int32, configuration: SecretFrontConfiguration) {
        self = Self()
        self.taskID = taskID
        append(
            String(
                format: String(localized: "SecretFrontTargetLog", defaultValue: "隐秘战线：目标结局 %@，指定事件：%@"),
                configuration.ending.rawValue, configuration.event.displayName))
    }

    mutating func observe(taskID: Int32, task: String, candidate: String? = nil) {
        guard self.taskID == taskID else { return }
        let step: String
        if task.hasPrefix("MiniGame@SecretFront@") {
            step = task.components(separatedBy: "@").last ?? task
        } else {
            // Core's external callback strips everything through the last @.
            // Bare names are safe only within this run's exact task ID and the
            // whitelist below; a foreign qualified task must remain rejected.
            guard !task.contains("@") else { return }
            step = task
        }
        let description: String
        switch step {
        case "SelectTeam": description = String(localized: "识别到分队选择页")
        case "Intelligence": description = String(localized: "选择情报侦察小队")
        case "Management": description = String(localized: "选择物资整备小队")
        case "Medicine": description = String(localized: "选择医疗救援小队")
        case "SelectTeamOK": description = String(localized: "确认出发")
        case "RouteSelect": description = String(localized: "识别路线，检查指定事件")
        case "PreClickDetect":
            if let candidate, !candidate.isEmpty {
                description = String(
                    format: String(localized: "SecretFrontCandidateLog", defaultValue: "检测到候选事件：%@"), candidate)
            } else {
                description = String(localized: "检查候选事件")
            }
        case "Actions": description = String(localized: "比较行动收益和成功率")
        case "ContinueResult": description = String(localized: "确认行动结果")
        case "ActionContinue": description = String(localized: "继续前进")
        case "EventContinue": description = String(localized: "识别到应对危机事件")
        case "EventDetected": description = String(localized: "按目标结局选择阶段路线")
        case "End": description = String(localized: "识别到终点画面")
        default: return
        }
        guard description != lastStep else { return }
        lastStep = description
        append(description)
    }

    mutating func finish(taskID: Int32, result: Result) {
        guard self.taskID == taskID else { return }
        switch result {
        case .completed: append(String(localized: "隐秘战线任务完成，请确认游戏结局"))
        case .stopped: append(String(localized: "隐秘战线已停止"))
        case .failed: append(String(localized: "隐秘战线任务失败，请检查游戏画面"))
        }
        if let lastStep {
            append(String(format: String(localized: "SecretFrontLastStepLog", defaultValue: "最后有效步骤：%@"), lastStep))
        }
        self.taskID = nil
    }

    mutating func release() { taskID = nil }

    private mutating func append(_ message: String) {
        messages.append(message)
        if messages.count > 200 { messages.removeFirst(messages.count - 200) }
    }
}

extension SecretFrontConfiguration.Event {
    var displayName: String {
        switch self {
        case .unspecified: String(localized: "不指定")
        case .support: String(localized: "支援作战平台")
        case .ranger: String(localized: "游侠")
        case .phantom: String(localized: "诡影迷踪")
        }
    }
}

/// Inspect the selected resource tree, never load a GUI-owned task override.
/// Presence is only a prerequisite: Core append validates task construction;
/// recognition and platform/OTA override behavior require runtime validation.
extension SecretFrontConfiguration {
    static func hasResources(in directory: URL) -> Bool {
        let candidates = ["tasks.json", "tasks/tasks.json", "tasks/MiniGame/SecretFront.json"]
        let required = ["Begin", "Run", "SelectTeam", "Actions", "End"]
            .map { "MiniGame@SecretFront@" + $0 }
        let definitions = candidates.compactMap { path -> [String: Any]? in
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(path)) else { return nil }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        guard required.allSatisfy({ key in definitions.contains { $0[key] != nil } }) else { return false }
        let templates = ["SelectTeam", "TeamManagement", "TeamIntelligence", "TeamMedicine"]
        return templates.allSatisfy { name in
            FileManager.default.fileExists(
                atPath:
                    directory
                    .appendingPathComponent("template/MiniGame/SecretFront/MiniGame@SecretFront@" + name + ".png").path)
        }
    }
}
