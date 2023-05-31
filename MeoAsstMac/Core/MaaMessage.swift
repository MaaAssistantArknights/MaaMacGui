//
//  MaaMessage.swift
//  MeoAsstMac
//
//  Created by hguandl on 9/10/2022.
//

import Foundation
import SwiftyJSON

struct MaaMessage {
    let code: Int
    let details: JSON
}

extension MAAViewModel {
    // MARK: - Process Message

    func processMessage(_ output: Notification) {
        guard let message = output.object as? MaaMessage else {
            return
        }

        switch message.code {
        case .InternalError:
            break

        case .InitFailed:
            // TODO: Show alert and shutdown
            break

        case .ConnectionInfo:
            processConnectionInfo(message)

        case .AllTasksCompleted, .TaskChainError ... .TaskChainStopped:
            processTaskChainMessage(message)

        case .SubTaskError ... .SubTaskExtraInfo:
            processSubTaskMessage(message)

        default:
            break
        }
    }

    // MARK: - Process Connection

    private func processConnectionInfo(_ message: MaaMessage) {
        guard let what = message.details["what"].string else {
            return
        }

        switch what {
        case "Connected":
            break

        case "UnsupportedResolution":
            logError("ResolutionNotSupported")

        case "ResolutionError":
            logError("ResolutionAcquisitionFailure")

        case "Reconnecting":
            let times = message.details["times"].int ?? 0 + 1
            logError("TryToReconnect %d", times)

        case "Reconnected":
            logTrace("ReconnectSuccess")

        case "Disconnect":
            // connected = false
            logError("ReconnectFailed")
            if status == .idle {
                break
            }

            Task {
                try await stop()
            }

            // If retryOnDisconnection, try to start emulator

        case "ScreencapFailed":
            logError("ScreencapFailed")

        case "TouchModeNotAvailable":
            logError("TouchModeNotAvaiable")

        case "UnsupportedPlayTools":
            logError("不支持此版本 PlayCover")

        default:
            break
        }
    }

    // MARK: - Process TaskChain

    private func processTaskChainMessage(_ message: MaaMessage) {
        guard let taskChain = message.details["taskchain"].string else {
            return
        }

        if taskChain == "CloseDown" {
            return
        }

        if taskChain == "Recruit" {
            if message.code == .TaskChainError {
                // Alert "IdentifyTheMistakes"
            }
        }

        switch message.code {
        case .TaskChainStopped:
            if let id = taskID(taskDetails: message.details) {
                taskStatus[id] = .cancel
            }
            resetStatus()
            logTrace("Stopped")

        case .TaskChainError:
            if let id = taskID(taskDetails: message.details) {
                taskStatus[id] = .failure
            }
            logError("TaskError %@", taskChain)

        case .TaskChainStart:
            if let id = taskID(taskDetails: message.details) {
                taskStatus[id] = .running
            }
            logTrace("StartTask %@", taskChain)

        case .TaskChainCompleted:
            if taskChain == "Infrast" {
                if let id = taskID(taskDetails: message.details),
                   let task = tasks[id],
                   case let .infrast(config) = task,
                   let plan = try? MAAInfrast(path: config.filename),
                   plan.plans.count > 0
                {
                    var newConfig = config
                    newConfig.plan_index = (config.plan_index + 1) % plan.plans.count
                    tasks[id] = .infrast(newConfig)
                }
            }

            if taskChain == "Mall" {
                // TODO: CreditFight
            }

            if let id = taskID(taskDetails: message.details) {
                taskStatus[id] = .success
            }

            logTrace("CompleteTask %@", taskChain)

        case .TaskChainExtraInfo:
            break

        case .AllTasksCompleted:
            resetStatus()
            logTrace("AllTasksComplete")

        default:
            break
        }
    }

    // MARK: - Process SubTask

    private func processSubTaskMessage(_ message: MaaMessage) {
        switch message.code {
        case .SubTaskError:
            processSubTaskError(message.details)

        case .SubTaskStart:
            processSubTaskStart(message.details)

        case .SubTaskCompleted:
            processSubTaskCompleted(message.details)

        case .SubTaskExtraInfo:
            processSubTaskExtraInfo(message.details)

        default:
            break
        }
    }

    private func processSubTaskError(_ details: JSON) {
        guard let subTask = details["subtask"].string else {
            return
        }

        switch subTask {
        case "StartGameTask":
            logError("FailedToOpenClient")

        case "AutoRecruitTask":
            let why = details["why"].string ?? "ErrorOccurred"
            logError("%@ HasReturned", why)

        case "RecognizeDrops":
            logError("DropRecognitionError")

        case "ReportToPenguinStats":
            let why = details["why"].string ?? "ErrorOccurred"
            logError("%@ GiveUpUploadingPenguins", why)

        case "CheckStageValid":
            logError("TheEX")

        default:
            break
        }
    }

    private func processSubTaskStart(_ details: JSON) {
        guard let subTask = details["subtask"].string else {
            return
        }

        switch subTask {
        case "ProcessTask":
            guard let taskName = details["details"]["task"].string,
                  let execTimes = details["details"]["exec_times"].int
            else {
                break
            }

            switch taskName {
            case "StartButton2", "AnnihilationConfirm":
                logInfo("MissionStart %d UnitTime", execTimes)

            case "MedicineConfirm":
                logInfo("MedicineUsed %d UnitTime", execTimes)

            case "StoneConfirm":
                logInfo("StoneUsed %d UnitTime", execTimes)

            case "AbandonAction":
                logError("ActingCommandError")

            case "RecruitRefreshConfirm":
                logInfo("LabelsRefreshed")

            case "RecruitConfirm":
                logInfo("RecruitConfirm")

            case "InfrastDormDoubleConfirmButton":
                logInfo("InfrastDormDoubleConfirmed")

            /// Tag: - 肉鸽相关
            case "StartExplore":
                logInfo("BegunToExplore %d UnitTime", execTimes)

            case "StageTraderInvestConfirm":
                logInfo("HasInvested %d UnitTime", execTimes)

            case "ExitThenAbandon":
                logTrace("ExplorationAbandoned")

            case "MissionCompletedFlag":
                logTrace("FightCompleted")

            case "MissionFailedFlag":
                logTrace("FightFailed")

            case "StageTraderEnter":
                logTrace("Trader")

            case "StageSafeHouseEnter":
                logTrace("SafeHouse")

            case "StageEncounterEnter":
                logTrace("Encounter")

            case "StageCambatDpsEnter":
                logTrace("CambatDps")

            case "StageEmergencyDps":
                logTrace("EmergencyDps")

            case "StageDreadfulFoe", "StageDreadfulFoe-5Enter":
                logTrace("DreadfulFoe")

            case "StageTraderInvestSystemFull":
                logInfo("UpperLimit")

            case "RestartGameAndContinue":
                logWarn("GameCrash")

            case "OfflineConfirm":
                // TODO: Auto-restart
                break

            case "GamePass":
                logRare("RoguelikeGamePass")

            case "BattleStartAll":
                logInfo("MissionStart")

            case "StageTraderSpecialShoppingAfterRefresh":
                logRare("RoguelikeSpecialItemBought")

            default:
                break
            }

        case "CombatRecordRecognitionTask":
            if let what = details["what"].string {
                logTrace(what)
            }

        default:
            break
        }
    }

    private func processSubTaskCompleted(_ details: JSON) {
        // Placeholder
    }

    private func processSubTaskExtraInfo(_ details: JSON) {
        guard let taskChain = details["taskchain"].string,
              let what = details["what"].string
        else {
            return
        }
        let subTaskDetails = details["details"]

        switch taskChain {
        case "Recruit":
            processRecruitMessage(details: details)

        case "VideoRecognition":
            processVideoMessage(details: details)

        case "Depot":
            depot = subTaskDetails.parseTo()

        case "OperBox":
            operBox = subTaskDetails.parseTo()

        default:
            break
        }

        switch what {
        case "StageDrops":
            guard let statistics = subTaskDetails["stats"].array else {
                return
            }

            var allDrops = [String]()
            for item in statistics {
                guard let name = item["itemName"].string,
                      let total = item["quantity"].int,
                      let addition = item["addQuantity"].int
                else {
                    continue
                }

                var drop = "\(name) : \(total)"
                if addition > 0 {
                    drop += " (+\(addition))"
                }
                allDrops.append(drop)
            }

            if allDrops.count == 0 {
                allDrops.append(NSLocalizedString("NoDrop", comment: ""))
            }
            logTrace(heading: "TotalDrop", allDrops)

        case "EnterFacility":
            guard let facility = subTaskDetails["facility"].string,
                  let index = subTaskDetails["index"].int
            else {
                break
            }
            logTrace("ThisFacility %@ %d", facility, index)

        case "ProductIncorrect":
            logError("ProductIncorrect")

        case "RecruitTagsDetected":
            guard let tags = subTaskDetails["tags"].array else {
                break
            }
            let tagNames = tags.compactMap(\.string)
            logTrace(heading: "RecruitingResults", tagNames)

        case "RecruitSpecialTag":
            if let special = subTaskDetails["tag"].string {
                _ = special
            }
            // TODO: Push Notification

        case "RecruitRobotTag":
            if let special = subTaskDetails["tag"].string {
                _ = special
            }
            // TODO: Push Notification

        case "RecruitResult":
            guard let level = subTaskDetails["level"].int else {
                break
            }
            if level >= 5 {
                // TODO: Push Notification
                // TODO: Bold
                logRare("\(level) ★ Tags")
            } else {
                logInfo("\(level) ★ Tags")
            }

        case "RecruitTagsSelect":
            guard let selected = subTaskDetails["tags"].array else {
                break
            }
            let selectedTags = selected.compactMap(\.string)
            if selectedTags.count > 0 {
                logTrace(heading: "Choose Tags", selectedTags)
            }

        case "RecruitTagsRefreshed":
            guard let count = subTaskDetails["count"].int else {
                break
            }
            logTrace("Refreshed %d UnitTime", count)

        case "NotEnoughStaff":
            logError("NotEnoughStaff")

        /// Tag: - Roguelike
        case "StageInfo":
            guard let name = subTaskDetails["name"].string else {
                break
            }
            logTrace("StartCombat %@", name)

        case "StageInfoError":
            logError("StageInfoError")

        case "PenguinId":
            if let id = subTaskDetails["id"].string {
                // Set viewModel id
                _ = id
            }

        case "BattleFormation":
            if let formation = subTaskDetails["formation"].rawString() {
                logTrace(["BattleFormation", formation])
            }

        case "BattleFormationSelected":
            if let selected = subTaskDetails["selected"].string {
                logTrace("BattleFormationSelected %@", selected)
            }

        case "CopilotAction":
            // TODO: b
            break

        case "SSSStage":
            if let stage = subTaskDetails["stage"].string {
                logInfo("CurrentStage %@", stage)
            }

        case "SSSSettlement":
            if let why = details["why"].string {
                logInfo(why)
            }

        case "SSSGamePass":
            logRare("SSSGamePass")

        case "UnsupportedLevel":
            logError("UnsupportedLevel")

        case "CustomInfrastRoomOperators":
            if let names = subTaskDetails["names"].array {
                let contents = names.compactMap(\.string).joined(separator: ", ")
                logTrace(contents)
            }

        case "ReclamationReport":
            // TODO: Complete this part when it comes back...
            break

        case "ReclamationProcedureStart":
            if let count = subTaskDetails["times"].int {
                logInfo("MissionStart %d UnitTime", count)
            }

        case "ReclamationSmeltGold":
            if let count = subTaskDetails["times"].int {
                logInfo("AlgorithmDoneSmeltGold %d UnitTime", count)
            }

        default:
            break
        }
    }

    // MARK: Recruit Recoginition

    private func processRecruitMessage(details: JSON) {
        guard let what = details["what"].string else {
            return
        }
        let subTaskDetails = details["details"]

        switch what {
        case "RecruitTagsDetected":
            break

        case "RecruitResult":
            if let result: MAARecruit = subTaskDetails.parseTo() {
                recruit = result
            }

        default:
            break
        }
    }

    // MARK: Video Recognition

    private func processVideoMessage(details: JSON) {
        guard let what = details["what"].string else {
            return
        }

        switch what {
        case "Finished":
            let filename = details["details"]["filename"].string ?? "No output"
            videoRecoginition = URL(fileURLWithPath: filename)
            logInfo("Save to %@", filename)

        default:
            break
        }
    }
}

// MARK: - AsstMsgId

private extension Int {
    /* Global Info */

    /// 内部错误
    static let InternalError = 0
    /// 初始化失败
    static let InitFailed = 1
    /// 连接相关信息
    static let ConnectionInfo = 2
    /// 全部任务完成
    static let AllTasksCompleted = 3
    /// 外部异步调用信息
    static let AsyncCallInfo = 4

    /* TaskChain Info */

    /// 任务链执行/识别错误
    static let TaskChainError = 10000
    /// 任务链开始
    static let TaskChainStart = 10001
    /// 任务链完成
    static let TaskChainCompleted = 10002
    /// 任务链额外信息
    static let TaskChainExtraInfo = 10003
    /// 任务链手动停止
    static let TaskChainStopped = 10004

    /* SubTask Info */

    /// 原子任务执行/识别错误
    static let SubTaskError = 20000
    /// 原子任务开始
    static let SubTaskStart = 20001
    /// 原子任务完成
    static let SubTaskCompleted = 20002
    /// 原子任务额外信息
    static let SubTaskExtraInfo = 20003
    /// 原子任务手动停止
    static let SubTaskStopped = 20004
}

// MARK: - Convenience Methods

extension MAAViewModel {
    func logTrace(_ key: String, comment: String = "", _ arguments: CVarArg...) {
        let content = localize(key, comment: comment, arguments)
        logs.append(MAALog(date: Date(), content: content, color: .trace))
    }

    func logTrace<S>(heading: String, _ contents: S) where S: Sequence, S.Element == String {
        let subs = contents.map { MAALog(date: nil, content: $0, color: .trace) }
        logs.append(MAALog(date: Date(), content: localize(heading), color: .trace))
        logs.append(contentsOf: subs)
    }

    func logTrace(_ contents: [String]) {
        guard contents.count > 1 else { return }
        logTrace(heading: contents[0], contents.dropFirst())
    }

    func logInfo(_ key: String, comment: String = "", _ arguments: CVarArg...) {
        let content = localize(key, comment: comment, arguments)
        logs.append(MAALog(date: Date(), content: content, color: .info))
    }

    func logWarn(_ key: String, comment: String = "", _ arguments: CVarArg...) {
        let content = localize(key, comment: comment, arguments)
        logs.append(MAALog(date: Date(), content: content, color: .warning))
    }

    func logRare(_ key: String, comment: String = "", _ arguments: CVarArg...) {
        let content = localize(key, comment: comment, arguments)
        logs.append(MAALog(date: Date(), content: content, color: .rare))
    }

    func logError(_ key: String, comment: String = "", _ arguments: CVarArg...) {
        let content = localize(key, comment: comment, arguments)
        logs.append(MAALog(date: Date(), content: content, color: .error))
    }

    private func localize(_ key: String, comment: String = "", _ arguments: CVarArg...) -> String {
        let format = NSLocalizedString(key, comment: comment)
        return String(format: format, arguments)
    }

    func taskID(taskDetails: JSON) -> UUID? {
        return taskID(coreID: taskDetails["taskid"].int32)
    }

    func taskID(coreID: Int32?) -> UUID? {
        if let coreID,
           let id = taskIDMap[coreID]
        {
            return id
        } else {
            return nil
        }
    }
}
