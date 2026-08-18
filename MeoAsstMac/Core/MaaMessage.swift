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

    func processMessage(_ message: MaaMessage) {
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
            isConnected = true

        case "UnsupportedResolution":
            isConnected = false
            logError("ResolutionNotSupported")

        case "ResolutionError":
            isConnected = false
            logError("ResolutionAcquisitionFailure")

        case "Reconnecting":
            let times = message.details["times"].int ?? 0 + 1
            logError("TryToReconnect (\(times))")

        case "Reconnected":
            isConnected = true
            logTrace("ReconnectSuccess")

        case "Disconnect":
            isConnected = false
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
            isConnected = false
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
            log("Stopped", color: .trace, splitMode: .both)

        case .TaskChainError:
            if let id = taskID(taskDetails: message.details) {
                taskStatus[id] = .failure
            }
            logError("TaskError \(taskChain)")
            if isCopilot {
                logError("CombatError")
            }

        case .TaskChainStart:
            if let id = taskID(taskDetails: message.details) {
                taskStatus[id] = .running
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
            }

        case .TaskChainExtraInfo:
            break

        case .AllTasksCompleted:
            log("AllTasksComplete", color: .trace, splitMode: .both)
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
                log("MissionStart \(execTimes) UnitTime", color: .info, splitMode: .before)

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
                log("BegunToExplore \(execTimes) UnitTime", color: .info, splitMode: .before)

            case "StageTraderInvestConfirm":
                logInfo("HasInvested \(execTimes) UnitTime")

            case "ExitThenAbandon":
                log("ExplorationAbandoned", color: .explorationAbandonedIS)

            case "MissionCompletedFlag":
                logTrace("FightCompleted")

            case "MissionFailedFlag":
                logTrace("FightFailed")

            case "StageTraderEnter":
                log("Trader", color: .traderIS)

            case "StageSafeHouseEnter":
                log("SafeHouse", color: .safehouseIS)

            case "StageEncounterEnter":
                log("Encounter", color: .eventIS)

            case "StageCombatOpsEnter":
                log("CombatOps", color: .combatIS)

            case "StageEmergencyOps":
                log("EmergencyOps", color: .emergencyIS)

            case "StageDreadfulFoe", "StageDreadfulFoe-5Enter":
                log("DreadfulFoe", color: .bossIS)

            case "StageTraderInvestSystemFull":
                logInfo("UpperLimit")

            case "RestartGameAndContinue":
                logWarn("GameCrash")

            case "OfflineConfirm":
                // TODO: Auto-restart
                logWarn("GameDrop")

            case "GamePass":
                log("RoguelikeGamePass", color: .rareOperator)

            case "BattleStartAll":
                log("MissionStart", color: .info, splitMode: .before)

            case "StageTraderSpecialShoppingAfterRefresh":
                log("RoguelikeSpecialItemBought", color: .rareOperator)

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

            struct DropEntry: Hashable {
                let name: String
                let total: Int
                let add: Int
            }

            var drops = statistics.compactMap { item -> DropEntry? in
                guard let name = item["itemName"].string,
                    let total = item["quantity"].int,
                    let add = item["addQuantity"].int
                else {
                    return nil
                }
                return DropEntry(name: name == "furni" ? String(localized: "FurnitureDrop") : name, total: total, add: add)
            }

            // 先按新增数量降序，再按总数量降序（对齐 Windows）
            drops.sort { a, b in
                if a.add != b.add { return a.add > b.add }
                return a.total > b.total
            }

            var allDrops = drops.map { drop -> String in
                var line = "\(drop.name) : \(drop.total)"
                if drop.add > 0 {
                    line += " (+\(drop.add))"
                }
                return line
            }

            if allDrops.isEmpty {
                allDrops.append(String(localized: "NoDrop"))
            }

            let stageCode = subTaskDetails["stage"]["stageCode"].string ?? ""
            var output = "\(stageCode) \(String(localized: "TotalDrop"))\n" + allDrops.joined(separator: "\n")
            if let curTimes = subTaskDetails["cur_times"].int, curTimes > 0 {
                output += "\n\(String(localized: "CurTimes")) : \(curTimes)"
            }
            if let weekly = subTaskDetails["annihilation_weekly_process"].array, weekly.count == 2 {
                output += "\n\(String(localized: "AnnihilationMode")) : \(weekly[0].intValue) / \(weekly[1].intValue)"
            }

            let tooltip = drops
                .filter { $0.add > 0 }
                .map { "\($0.name) : \($0.total) (+\($0.add))" }
                .joined(separator: "\n")

            let sanityLeft = self.curSanityBeforeFight - self.sanityCost
            output += "\n" + String(localized: "SanityLeft") + ": \(sanityLeft >= 0 ? String(sanityLeft) : "Error")"
            writeLog(output, color: .success, toolTip: tooltip, splitMode: .before, updateCardImage: true)

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
            log("RecruitingResults: \(tagNames.joined(separator: ", "))", color: .trace, splitMode: .before)

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
            let tooltip = recruitResultTooltip(details: subTaskDetails)
            if level >= 5 {
                // TODO: Push Notification
                log("\(level) ★ Tags", color: .rareOperator, weight: .bold, toolTip: tooltip)
            } else {
                log("\(level) ★ Tags", color: .info, toolTip: tooltip)
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
            log("StageInfoError", color: .error, splitMode: .both, updateCardImage: true)

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
            log("SSSGamePass", color: .rareOperator)

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
        writeLog(String(localized: key, comment: comment), color: .trace)
    }

    func logInfo(_ key: String.LocalizationValue, comment: StaticString? = nil) {
        writeLog(String(localized: key, comment: comment), color: .info)
    }

    func logWarn(_ key: String.LocalizationValue, comment: StaticString? = nil) {
        writeLog(String(localized: key, comment: comment), color: .warning)
    }

    func logRare(_ key: String.LocalizationValue, comment: StaticString? = nil) {
        writeLog(String(localized: key, comment: comment), color: .rare)
    }

    func logError(_ key: String.LocalizationValue, comment: StaticString? = nil) {
        writeLog(String(localized: key, comment: comment), color: .error)
    }

    func logSuccess(_ key: String.LocalizationValue, comment: StaticString? = nil) {
        writeLog(String(localized: key, comment: comment), color: .success)
    }

    func logMessage(_ key: String.LocalizationValue, comment: StaticString? = nil) {
        writeLog(String(localized: key, comment: comment), color: .message)
    }

    func logDownload(_ key: String.LocalizationValue, comment: StaticString? = nil) {
        writeLog(String(localized: key, comment: comment), color: .download)
    }

    /// 构建公招结果的 tooltip（标签 + 可能干员，对齐 Windows `RecruitResultInlines`）。
    private func recruitResultTooltip(details: JSON) -> String? {
        guard let results = details["result"].array else {
            return nil
        }
        var lines = [String]()
        for combo in results {
            let tags = combo["tags"].array?.compactMap(\.string).joined(separator: "、") ?? ""
            let opers = combo["opers"].array?.compactMap { $0["name"].string }.joined(separator: "、") ?? ""
            if !tags.isEmpty {
                lines.append(tags)
            }
            if !opers.isEmpty {
                lines.append("   " + opers)
            }
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
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
