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
            logError("TryToReconnect (\(times))")

        case "Reconnected":
            logTrace("ReconnectSuccess")

        case "Disconnect":
            logError("ReconnectFailed")
            if status == .idle {
                break
            }
            Task {
                try await stop()
            }
        // TODO: If retryOnDisconnection, try to start emulator

        case "ScreencapFailed":
            logError("ScreencapFailed")

        case "TouchModeNotAvailable":
            logError("TouchModeNotAvaiable")

        case "FastestWayToScreencap":
            let cost = message.details["details"]["cost"].number?.stringValue ?? "???"
            let method = message.details["details"]["method"].string ?? "???"
            logInfo("FastestWayToScreencap: \(cost)ms (\(method))")

        case "ScreencapCost":
            let minCost = message.details["details"]["min"].number?.stringValue ?? "???"
            let avgCost = message.details["details"]["avg"].number?.stringValue ?? "???"
            let maxCost = message.details["details"]["max"].number?.stringValue ?? "???"
            logInfo("ScreencapCost: \(minCost) / \(avgCost) / \(maxCost)")

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

        let isCopilot = ["Copilot", "VideoRecognition"].contains(taskChain)

        if taskChain == "CloseDown" {
            Task {
                try await stop()
            }
        }

        if taskChain == "Recruit" {
            if message.code == .TaskChainError {
                logError("IdentifyTheMistakes")
                // TODO: Alert "IdentifyTheMistakes"
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
            logError("TaskError \(taskChain)")
            if isCopilot {
                logError("CombatError")
                if isCopilotListRunning {
                    Task { try await stop() }
                    self.copilotListConfig = copilotListConfig
                    if let stage = getCurrentCopilotStageName() {
                        logError("战斗出错：\(stage)")
                    }
                    isCopilotListRunning = false
                    logError("CopilotListError")
                }
            }

        case .TaskChainStart:
            if let id = taskID(taskDetails: message.details) {
                taskStatus[id] = .running
            }
            if isCopilot, let stage = getCurrentCopilotStageName() {
                logInfo("开始关卡：\(stage)")
            }
            logTrace("StartTask \(taskChain)")

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

            logTrace("CompleteTask \(taskChain)")

            if isCopilot {
                logInfo("CompleteCombat")
                if isCopilotListRunning {
                    if let stage = getCurrentCopilotStageName() {
                        logInfo("完成关卡：\(stage)")
                    }
                    if let idx = copilotListConfig.items.firstIndex(where: { $0.enabled }) {
                        copilotListConfig.items[idx].enabled = false
                        self.copilotListConfig = copilotListConfig
                    }
                }
            }

        case .TaskChainExtraInfo:
            break

        case .AllTasksCompleted:
            logTrace("AllTasksComplete")
            if isCopilotListRunning {
                logInfo("CopilotListCompleted")
                isCopilotListRunning = false
            }
            resetStatus()

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
            let why = details["why"].string ?? String(localized: "ErrorOccurred")
            logError("\(why) HasReturned")

        case "RecognizeDrops":
            logError("DropRecognitionError")

        case "ReportToPenguinStats":
            let why = details["why"].string ?? String(localized: "ErrorOccurred")
            logError("\(why) GiveUpUploadingPenguins")

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
                logInfo("MissionStart \(execTimes) UnitTime")

            case "StoneConfirm":
                logInfo("StoneUsed \(execTimes) UnitTime")

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
                logInfo("BegunToExplore \(execTimes) UnitTime")

            case "StageTraderInvestConfirm":
                logInfo("HasInvested \(execTimes) UnitTime")

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
                logWarn("GameDrop")

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
                logTrace("\(what)")
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

            let sanityLeft = self.curSanityBeforeFight - self.sanityCost
            logTrace(
                "TotalDrop\n\(allDrops.joined(separator: "\n"))\n\nSanityLeft: \(sanityLeft >= 0 ? String(sanityLeft) : "Error")"
            )

        case "EnterFacility":
            guard let facility = subTaskDetails["facility"].string,
                let index = subTaskDetails["index"].int
            else {
                break
            }
            logTrace("ThisFacility \(facility) \(index)")

        case "ProductIncorrect":
            logError("ProductIncorrect")

        case "RecruitTagsDetected":
            guard let tags = subTaskDetails["tags"].array else {
                break
            }
            let tagNames = tags.compactMap(\.string)
            logTrace("RecruitingResults: \(tagNames.joined(separator: ", "))")

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
                logTrace("Choose Tags: \(selectedTags.joined(separator: ", "))")
            }

        case "RecruitTagsRefreshed":
            guard let count = subTaskDetails["count"].int else {
                break
            }
            logTrace("Refreshed \(count) UnitTime")

        case "NotEnoughStaff":
            logError("NotEnoughStaff")

        /// Tag: - Roguelike
        case "StageInfo":
            guard let name = subTaskDetails["name"].string else {
                break
            }
            logTrace("StartCombat \(name)")

        case "StageInfoError":
            logError("StageInfoError")

        case "PenguinId":
            if let id = subTaskDetails["id"].string {
                // Set viewModel id
                _ = id
            }

        case "BattleFormation":
            if let formation = subTaskDetails["formation"].rawString() {
                logTrace("BattleFormation: \(formation)")
            }

        case "BattleFormationSelected":
            if let selected = subTaskDetails["selected"].string {
                logTrace("BattleFormationSelected \(selected)")
            }

        case "CopilotAction":
            // TODO: b
            break

        case "SSSStage":
            if let stage = subTaskDetails["stage"].string {
                logInfo("CurrentStage \(stage)")
            }

        case "SSSSettlement":
            if let why = details["why"].string {
                logInfo("\(why)")
            }

        case "SSSGamePass":
            logRare("SSSGamePass")

        case "UnsupportedLevel":
            logError("UnsupportedLevel")

        case "CustomInfrastRoomOperators":
            if let names = subTaskDetails["names"].array {
                let contents = names.compactMap(\.string).joined(separator: ", ")
                logTrace("\(contents)")
            }

        case "ReclamationReport":
            // TODO: Complete this part when it comes back...
            break

        case "ReclamationProcedureStart":
            if let count = subTaskDetails["times"].int {
                logInfo("MissionStart \(count) UnitTime")
            }

        case "ReclamationSmeltGold":
            if let count = subTaskDetails["times"].int {
                logInfo("AlgorithmDoneSmeltGold \(count) UnitTime")
            }

        case "RoguelikeCollapsalParadigms":
            if let cur = subTaskDetails["cur"].string,
                let deepen_or_weaken = subTaskDetails["deepen_or_weaken"].int,
                deepen_or_weaken == 1
            {
                logInfo("GainParadigm \(cur)")
            }

        case "UseMedicine":
            if let isExpiringMedicine = subTaskDetails["is_expiring"].bool,
                let medicineCount = subTaskDetails["count"].int
            {
                if !isExpiringMedicine {
                    medicineUsedTimes += medicineCount
                    logInfo("MedicineUsed \(medicineUsedTimes)(+\(medicineCount)) UnitTime")
                } else {
                    expiringMedicineUsedTimes += medicineCount
                    logInfo("ExpiringMedicineUsed \(expiringMedicineUsedTimes)(+\(medicineCount)) UnitTime")
                }
            }

        case "SanityBeforeStage":
            if let curSanityBeforeFight = subTaskDetails["current_sanity"].int {
                self.curSanityBeforeFight = curSanityBeforeFight
            }

        case "FightTimes":
            if let sanityCost = subTaskDetails["sanity_cost"].int {
                self.sanityCost = sanityCost
            }

        default:
            break
        }
    }

    // MARK: - Recruit Recoginition

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

    // MARK: - Video Recognition

    private func processVideoMessage(details: JSON) {
        guard let what = details["what"].string else {
            return
        }

        switch what {
        case "Finished":
            let filename = details["details"]["filename"].string ?? "No output"
            videoRecoginition = URL(fileURLWithPath: filename)
            logInfo("Save to \(filename)")

        default:
            break
        }
    }
}

// MARK: - AsstMsgId

extension Int {
    /* Global Info */

    /// 内部错误
    fileprivate static let InternalError = 0
    /// 初始化失败
    fileprivate static let InitFailed = 1
    /// 连接相关信息
    fileprivate static let ConnectionInfo = 2
    /// 全部任务完成
    fileprivate static let AllTasksCompleted = 3
    /// 外部异步调用信息
    fileprivate static let AsyncCallInfo = 4

    /* TaskChain Info */

    /// 任务链执行/识别错误
    fileprivate static let TaskChainError = 10000
    /// 任务链开始
    fileprivate static let TaskChainStart = 10001
    /// 任务链完成
    fileprivate static let TaskChainCompleted = 10002
    /// 任务链额外信息
    fileprivate static let TaskChainExtraInfo = 10003
    /// 任务链手动停止
    fileprivate static let TaskChainStopped = 10004

    /* SubTask Info */

    /// 原子任务执行/识别错误
    fileprivate static let SubTaskError = 20000
    /// 原子任务开始
    fileprivate static let SubTaskStart = 20001
    /// 原子任务完成
    fileprivate static let SubTaskCompleted = 20002
    /// 原子任务额外信息
    fileprivate static let SubTaskExtraInfo = 20003
    /// 原子任务手动停止
    fileprivate static let SubTaskStopped = 20004
}

// MARK: - Convenience Methods

extension MAAViewModel {
    func logTrace(_ key: String.LocalizationValue, comment: StaticString? = nil) {
        writeLog(color: .trace, key, comment: comment)
    }

    func logInfo(_ key: String.LocalizationValue, comment: StaticString? = nil) {
        writeLog(color: .info, key, comment: comment)
    }

    func logWarn(_ key: String.LocalizationValue, comment: StaticString? = nil) {
        writeLog(color: .warning, key, comment: comment)
    }

    func logRare(_ key: String.LocalizationValue, comment: StaticString? = nil) {
        writeLog(color: .rare, key, comment: comment)
    }

    func logError(_ key: String.LocalizationValue, comment: StaticString? = nil) {
        writeLog(color: .error, key, comment: comment)
    }

    private func writeLog(color: MAALog.LogColor, _ key: String.LocalizationValue, comment: StaticString?) {
        let content = String(localized: key, comment: comment)
        let entry = MAALog(date: Date(), content: content, color: color)
        logs.append(entry)
        fileLogger.write(entry)
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
