//
//  MaaMessage.swift
//  MeoAsstMac
//
//  Created by hguandl on 9/10/2022.
//

import Foundation
import JBird
import OSLog

struct MaaMessage: Hashable {
    let code: Int
    let details: JSON
}

private let logger = Logger(subsystem: "com.hguandl.MeoAsstMac", category: "MaaMessage")

extension JSONInitializable {
    fileprivate init?(json: JSON, context: String) {
        do {
            self = try Self(json: json)
        } catch {
            logger.error("Failed to parse \(context): \(error); details: \(json)")
            return nil
        }
    }
}

private func decodeMessage<T: Decodable>(_ type: T.Type, from json: JSON, context: String) -> T? {
    do {
        let data = try json.serialize()
        return try JSON.Decoder().decode(T.self, from: data)
    } catch {
        logger.error("Failed to decode \(context): \(error); details: \(json)")
        return nil
    }
}

// MARK: - Process Message

extension MAAViewModel {
    func processMessage(_ message: MaaMessage) {
        switch message.code {
        case .InternalError, .InitFailed:
            // Currently not emitted by Core.
            break

        case .ConnectionInfo:
            processConnectionInfo(message)

        case .AsyncCallInfo:
            assert(false, "Should have been processed in MAAHandle")

        case .Destroyed:
            // MAAHandle remains valid throughout the current lifecycle.
            break

        case .AllTasksCompleted, .TaskChainError ... .TaskChainStopped:
            processTaskChainMessage(message)

        case .SubTaskError ... .SubTaskExtraInfo:
            processSubTaskMessage(message)

        case .SubTaskStopped:
            // Currently not emitted by Core.
            break

        case .ReportRequest:
            // TODO: Perform the HTTP data-reporting request provided by Core.
            break

        default:
            logger.warning("Unhandled MaaMessage code: \(message.code)")
        }
    }
}

// MARK: - Process Connection

extension MAAViewModel {
    private func processConnectionInfo(_ message: MaaMessage) {
        let details = message.details
        guard let what: String = try? details["what"] else {
            return
        }

        func resolution(details: JSON) -> (width: Int, height: Int)? {
            guard let width: Int = try? details["details"]["width"],
                let height: Int = try? details["details"]["height"]
            else {
                return nil
            }
            return (width, height)
        }

        switch what {
        case "Connected":
            if let address: String = try? details["details"]["address"] {
                logInfo("已连接至 \(address)")
            }

        case "UnsupportedResolution":
            if let (width, height) = resolution(details: details), width > 0, height > 0 {
                logError("ResolutionNotSupportedCurrentResolution \(width) \(height)")
            } else {
                logError("ResolutionNotSupported")
            }

        case "ResolutionInfo":
            if let (width, height) = resolution(details: details) {
                if clientChannel == .YoStarEN, width != 1920 || height != 1080 {
                    logError("ResolutionInfoYoStarEN")
                }
            }

        case "MuMuExtrasInputStatus":
            // Not available on macOS
            break

        case "ResolutionError":
            logError("ResolutionAcquisitionFailure")

        case "Reconnecting":
            guard let times: Int = try? details["details"]["times"] else {
                return
            }
            logError("TryToReconnect \(times + 1)")

        case "Reconnected":
            logTrace("ReconnectSuccess")

        case "Disconnect":
            logError("ReconnectFailed")
            if status == .idle {
                break
            }
            Task {
                do {
                    try await stop()
                } catch {
                    logger.warning("Failed to stop after Disconnect: \(error)")
                }
            }

        case "ScreencapFailed":
            logError("ScreencapFailed")

        case "TouchModeNotAvailable":
            logError("TouchModeNotAvailable")

        case "FastestWayToScreencap":
            guard let cost: Int = try? details["details"]["cost"],
                let method: String = try? details["details"]["method"]
            else {
                return
            }
            if cost > 400 {
                logWarn("FastestWayToScreencap \(cost) \(method)")
            } else {
                logTrace("FastestWayToScreencap \(cost) \(method)")
            }

        case "ScreencapCost":
            guard let minimum: Int = try? details["details"]["min"],
                let maximum: Int = try? details["details"]["max"],
                let average: Int = try? details["details"]["avg"]
            else {
                return
            }
            logStore?.screencapCost = (minimum, maximum, average)
            let level: Int
            switch average {
            case 800...:
                level = 800
            case 400...:
                level = 400
            default:
                level = 0
            }
            guard level > logStore?.lastScreencapWarningLevel ?? 0 else {
                return
            }
            switch level {
            case 800:
                logWarn("FastestWayToScreencapErrorTip \(average)")
            case 400:
                logWarn("FastestWayToScreencapWarningTip \(average)")
            default:
                break
            }
            logStore?.lastScreencapWarningLevel = level

        case "EmulatorFPS":
            guard let fps: Int = try? details["details"]["fps"] else {
                return
            }
            switch fps {
            case ...0, 60:
                break
            case ..<30:
                logError("EmulatorFpsErrorTip \(fps)")
            case ..<60:
                logWarn("EmulatorFpsWarningTip \(fps)")
            default:
                if logStore?.hasPrintedFPSHighTip != true {
                    logWarn("EmulatorFpsHighTip \(fps)")
                    logStore?.hasPrintedFPSHighTip = true
                }
            }

        case "UnsupportedPlayTools":
            logError("不支持此版本 PlayCover")

        default:
            break
        }
    }
}

// MARK: - Process TaskChain

@JSONRepresentable
private struct TaskChainMessage {
    let taskchain: String
    let taskid: Int32
}

extension MAAViewModel {
    private func processTaskChainMessage(_ message: MaaMessage) {
        if message.code == .AllTasksCompleted {
            resetStatus()
            guard let ids: [Int32] = try? message.details["finished_tasks"] else {
                return
            }

            for id in ids {
                if let uuid = taskID(coreID: id), let task = tasks[uuid] {
                    if case .closedown = task {
                        continue
                    }
                    logTrace("AllTasksComplete")
                    // TODO: Align elapsed time, sanity report, notifications, and post-task actions.
                    break
                }
            }

            return
        }

        guard let info = TaskChainMessage(json: message.details, context: "TaskChain") else {
            return
        }

        if info.taskchain == "CloseDown" {
            return
        }

        if info.taskchain == "Recruit", message.code == .TaskChainError {
            let resource = LocalizedStringResource("IdentifyTheMistakes")
            // TODO: Push user notification of this error message.
            // TODO: Show this error message in RecruitView.
            _ = resource
        }

        let isCopilot = ["Copilot", "SSSCopilot"].contains(info.taskchain)

        let taskChain = Bundle.main.localizedString(forKey: info.taskchain, value: nil, table: nil)

        switch message.code {
        case .TaskChainStopped:
            if let id = taskID(coreID: info.taskid) {
                taskStatus[id] = .cancel
            }
            resetStatus()
            logTrace("Stopped")

        case .TaskChainError:
            if let id = taskID(coreID: info.taskid) {
                taskStatus[id] = .failure
            }
            logError("TaskError \(taskChain)")
            if isCopilot {
                logError("CombatError")
            }
        // TODO: Align screenshot/card updates and notifications.

        case .TaskChainStart:
            if let id = taskID(coreID: info.taskid) {
                taskStatus[id] = .running
            }
            logTrace("StartTask \(taskChain)")
        // TODO: Use the configured task display name.

        case .TaskChainCompleted:
            if info.taskchain == "Infrast" {
                if let id = taskID(coreID: info.taskid),
                    let task = tasks[id],
                    case .infrast(let config) = task,
                    config.mode == .custom,
                    let plan = try? MAAInfrast(path: config.filename),
                    plan.plans.count > 0
                {
                    var newConfig = config
                    newConfig.plan_index = (config.plan_index + 1) % plan.plans.count
                    tasks[id] = .infrast(newConfig)
                }
            }
            // TODO: Align WPF plan-index validation and custom-plan switch logs.

            if let id = taskID(coreID: info.taskid) {
                taskStatus[id] = .success
            }

            logTrace("CompleteTask \(taskChain)")
        // TODO: Align the sanity report.

        case .TaskChainExtraInfo:
            let what: String? = try? message.details["what"]
            let why: String? = try? message.details["why"]
            if what == "RoutingRestart", why == "TooManyBattlesAhead" {
                if let nodeCost: Int = try? message.details["node_cost"] {
                    logWarn("RoutingRestartTooManyBattles \(nodeCost)")
                }
            }

        default:
            break
        }
    }
}

// MARK: - Process SubTask

extension MAAViewModel {
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
}

// MARK: - Process SubTask Error

@JSONRepresentable
private struct SubTaskErrorMessage {
    let subtask: String
    let why: String?
    let what: String?
    let details: JSON?
    let taskid: Int32?
}

extension MAAViewModel {
    private func processSubTaskError(_ details: JSON) {
        guard let info = SubTaskErrorMessage(json: details, context: "SubTaskError") else {
            return
        }

        switch info.subtask {
        case "StartGameTask":
            logError("FailedToOpenClient")

        case "StopGameTask":
            logError("CloseArknightsFailed")

        case "AutoRecruitTask":
            let why = info.why ?? String(localized: "ErrorOccurred")
            logError("HasReturned \(why)")

        case "RecognizeDrops":
            logError("DropRecognitionError")

        case "ReportToPenguinStats":
            let why = info.why ?? String(localized: "ErrorOccurred")
            logWarn("GiveUpUploadingPenguins \(why)")
        // TODO: Use the annihilation-specific message when the failed task is an annihilation fight.

        case "CheckStageValid":
            logError("TheEx")

        case "BattleFormationTask":
            if info.why == "OperatorMissing" {
                // TODO: Parse grouped missing operators and output MissingOperators.
            }

        case "CopilotTask":
            if info.what == "UserAdditionalOperInvalid", let payload = info.details,
                let name: String = try? payload["name"]
            {
                logError("CopilotUserAdditionalNameInvalid \(name)")
            }

        default:
            break
        }
    }
}

// MARK: - Process SubTask Start

@JSONRepresentable
private struct SubTaskStartMessage {
    let subtask: String
    let what: String?
    let details: JSON?
}

@JSONRepresentable
private struct ProcessTaskDetails {
    let task: String
    let exec_times: Int
}

extension MAAViewModel {
    private func processSubTaskStart(_ details: JSON) {
        guard let info = SubTaskStartMessage(json: details, context: "SubTaskStart") else {
            return
        }

        switch info.subtask {
        case "ProcessTask":
            guard let payload = info.details,
                let process = ProcessTaskDetails(json: payload, context: "ProcessTaskStart")
            else {
                return
            }

            switch process.task {
            case "StartButton2", "AnnihilationConfirm":
                logInfo("MissionStart.FightTask \(process.exec_times) \(sanityCost)")
            // TODO: Align fight-series, sanity, medicine, stone, and screenshot-card details.

            case "StoneConfirm":
                logInfo("StoneUsed \(process.exec_times)")
            // TODO: Track the stone-use count.

            case "AbandonAction":
                logError("ActingCommandError")

            case "FightMissionFailedAndStop":
                logError("FightMissionFailedAndStop")
            // TODO: Show the matching notification.

            case "CheckEncounter-Uncollected":
                logWarn("MiniGame@InteractiveExhibition@UncollectedNotificationContent")
            // TODO: Align screenshot-card, toast, and external notification behavior.

            case "RecruitRefreshConfirm":
                logInfo("LabelsRefreshed")

            case "RecruitConfirm":
                logInfo("RecruitConfirm")
            // TODO: Track recruit confirmations and update the screenshot card.

            case "InfrastDormDoubleConfirmButton":
                logError("InfrastDormDoubleConfirmed")

            case "ExitThenAbandon":
                logWarn("ExplorationAbandoned")

            case "StartAction":
                // WPF retains this callback branch but currently performs no operation.
                break

            case "MissionCompletedFlag":
                logInfo("FightCompleted")
            // TODO: Update the screenshot card.

            case "MissionFailedFlag":
                logError("FightFailed")
            // TODO: Update the screenshot card.

            case "StageTrader":
                logInfo("Trader")

            case "StageSafeHouse":
                logInfo("SafeHouse")

            case "StageFilterTruth":
                logInfo("FilterTruth")

            case "StageBoonsEnter":
                // WPF retains this callback branch but currently performs no operation.
                break

            case "StageCombatOps":
                logInfo("CombatOps")

            case "StageEmergencyOps":
                logWarn("EmergencyOps")

            case "StageDreadfulFoe", "StageDreadfulFoe-5":
                logError("DreadfulFoe")

            case "StageTraderInvestSystemFull":
                logInfo("UpperLimit")

            case "OfflineConfirm", "OfflineConfirmAfterBattle":
                logWarn("GameDrop")
                Task {
                    do {
                        try await stop()
                    } catch {
                        logger.warning("Failed to stop after game disconnect: \(error)")
                    }
                }
            // TODO: Align the toast notification.

            case "GamePass":
                logRare("RoguelikeGamePass")

            case "BattleStartAll":
                logInfo("MissionStart")

            case "StageDrops-Stars-3", "StageDrops-Stars-Adverse":
                logInfo("CompleteCombat")
            // TODO: Mark the Copilot task successful.

            case "StageTraderSpecialShoppingAfterRefresh":
                logRare("RoguelikeSpecialItemBought")

            case "DeepExplorationNotUnlockedComplain":
                logWarn("DeepExplorationNotUnlockedComplain")

            case "PNS-Resume":
                logError("ReclamationPnsModeError")

            case "PIS-Commence":
                logError("ReclamationPisModeError")

            default:
                break
            }

        case "CombatRecordRecognitionTask":
            if let what = info.what {
                logTrace("\(what)")
            }

        default:
            break
        }
    }
}

// MARK: - Process SubTask Completed

@JSONRepresentable
private struct SubTaskCompletedMessage {
    let subtask: String
    let taskchain: String?
    let taskid: Int32?
    let details: JSON?
}

extension MAAViewModel {
    private func processSubTaskCompleted(_ details: JSON) {
        guard let info = SubTaskCompletedMessage(json: details, context: "SubTaskCompleted") else {
            return
        }
        guard info.subtask == "ProcessTask", let payload = info.details,
            let process = ProcessTaskDetails(json: payload, context: "ProcessTaskCompleted")
        else {
            return
        }

        switch info.taskchain {
        case "Infrast":
            switch process.task {
            case "UnlockClues":
                logTrace("ClueExchangeUnlocked")
            case "SendClues":
                // WPF retains this callback branch; macOS deliberately performs no operation.
                break
            default:
                break
            }

        case "Roguelike":
            if process.task == "StartExplore" {
                logInfo("BegunToExplore \(process.exec_times)")
            }

        case "Mall":
            switch process.task {
            case "StageDrops-Stars-3":
                let taskName = LocalizedStringResource("CreditFight")
                logInfo("CompleteTask \(taskName)")
            // TODO: Persist the credit-fight date.
            case "VisitLimited", "VisitNextBlack":
                let taskName = LocalizedStringResource("Visiting")
                logInfo("CompleteTask \(taskName)")
            // TODO: Persist the friend-visit date.
            default:
                break
            }

        default:
            break
        }
    }
}

// MARK: - Process SubTask Extra Info

@JSONRepresentable
private struct SubTaskExtraInfoMessage {
    let taskchain: String
    let what: String
    let details: JSON
    let why: String?
    let taskid: Int32?
}

@JSONRepresentable
private struct StageDropItemDetails {
    let itemName: String
    let quantity: Int
    let addQuantity: Int
}

@JSONRepresentable
private struct StageDropStageDetails {
    let stageCode: String?
}

@JSONRepresentable
private struct StageDropsDetails {
    let stats: [StageDropItemDetails]
    let stage: StageDropStageDetails?
    let cur_times: Int?
}

@JSONRepresentable
private struct CopilotActionDetails {
    let action: String
    let target: String?
    let doc: String?
    let doc_color: String?
    let elapsed_time: Int?
}

@JSONRepresentable
private struct CopilotFileDetails {
    let file_name: String
    let stage_name: String
    let id: Int?
}

@JSONRepresentable
private struct RoguelikeInvestmentDetails {
    let count: Int
    let total: Int
    let deposit: Int
}

@JSONRepresentable
private struct RoguelikeSettlementDetails {
    let game_pass: Bool
    let floor: Int?
    let step: Int?
    let combat: Int?
    let emergency: Int?
    let boss: Int?
    let recruit: Int?
    let collection: Int?
    let difficulty: Int?
    let score: Int?
    let exp: String?
    let skill: String?
}

@JSONRepresentable
private struct RoguelikeEncounterOptionDetails {
    let enabled: Bool
    let text: String
}

@JSONRepresentable
private struct BlackFlowRoutingDecisionDetails {
    let floor: Int
    let action_points_before: Int
    let action_points_after: Int
    let movement: String
    let node_name: String?
    let node_type: String
    let safety_margin: Int
    let reason_category: String
    let reason_detail: String?
}

@JSONRepresentable
private struct MedicineItemDetails {
    let use: Int
    let inventory: Int
}

@JSONRepresentable
private struct UseMedicineDetails {
    let is_expiring: Bool
    let count: Int
    let medicines: [MedicineItemDetails]?
}

extension MAAViewModel {
    private func processSubTaskExtraInfo(_ details: JSON) {
        guard let info = SubTaskExtraInfoMessage(json: details, context: "SubTaskExtraInfo") else {
            return
        }

        switch info.taskchain {
        case "Recruit":
            // TODO: Align WPF's general recruit-calculation state update for every Recruit callback.
            break

        case "Depot":
            depot = decodeMessage(MAADepot.self, from: info.details, context: "Depot")
        // TODO: Record the synchronization time and associate the result with taskid.

        case "OperBox":
            operBox = decodeMessage(MAAOperBox.self, from: info.details, context: "OperBox")
        // TODO: Record the synchronization time and associate the result with taskid.

        default:
            break
        }

        switch info.what {
        case "StageDrops":
            guard let dropInfo = StageDropsDetails(json: info.details, context: "StageDrops") else {
                return
            }
            let drops = dropInfo.stats
                .sorted {
                    ($0.addQuantity, $0.quantity) > ($1.addQuantity, $1.quantity)
                }
                .map { item in
                    item.addQuantity > 0
                        ? "\(item.itemName) : \(item.quantity) (+\(item.addQuantity))"
                        : "\(item.itemName) : \(item.quantity)"
                }
            let noDrop = LocalizedStringResource("NoDrop")
            let dropText = drops.isEmpty ? String(localized: noDrop) : drops.joined(separator: "\n")
            let stageCode = dropInfo.stage?.stageCode ?? ""
            let totalDrop = LocalizedStringResource("TotalDrop")
            if let curTimes = dropInfo.cur_times, curTimes > 0 {
                let currentTimes = LocalizedStringResource("CurTimes")
                logTrace("\(stageCode) \(totalDrop)\n\(dropText)\n\(currentTimes) : \(curTimes)")
            } else {
                logTrace("\(stageCode) \(totalDrop)\n\(dropText)")
            }
        // TODO: Align furniture naming, stage/current-times details, tooltip, screenshot card,
        // and depot synchronization.

        case "EnterFacility":
            let facility: String = (try? info.details["facility"]) ?? ""
            let index: Int = (try? info.details["index"]) ?? -2
            logTrace("ThisFacility \(facility) \(String(format: "%02d", index + 1))")
        // TODO: Align log-card splitting.

        case "ProductIncorrect":
            logError("ProductIncorrect")

        case "ProductUnknown":
            logError("ProductUnknown")

        case "ProductChanged":
            logInfo("ProductChanged")

        case "ProductChangeFail":
            logError("ProductChangeFail")

        case "InfrastConfirmButton":
            // TODO: Fetch the latest screenshot and update the log card.
            break

        case "RecruitTagsDetected":
            let tags: [String] = (try? info.details["tags"]) ?? []
            let tagText = tags.isEmpty ? String(localized: "Error") : tags.joined(separator: "\n")
            logTrace("RecruitingResults \(tagText)")
        // TODO: Align log-card splitting and screenshot updates.

        case "RecruitSpecialTag", "RecruitRobotTag":
            guard let _: String = try? info.details["tag"] else {
                return
            }
        // TODO: Show the corresponding recruit notification.

        case "RecruitPreservedTag":
            guard let tag: String = try? info.details["tag"] else {
                return
            }
            logTrace("RecruitingTips \(tag)")
        // TODO: Show the corresponding recruit notification.

        case "RecruitResult":
            guard let level: Int = try? info.details["level"] else {
                return
            }
            if level >= 5 {
                logRare("\(level) ★ Tags")
            } else {
                logInfo("\(level) ★ Tags")
            }
            recruit = decodeMessage(MAARecruit.self, from: info.details, context: "RecruitResult")
        // TODO: Align tooltip, emphasis, and notification.

        case "RecruitSupportOperator":
            guard let name: String = try? info.details["name"] else {
                return
            }
            logInfo("RecruitSupportOperator \(name)")

        case "RecruitTagsSelected":
            let tags: [String] = (try? info.details["tags"]) ?? []
            let selected = tags.isEmpty ? String(localized: "NoDrop") : tags.joined(separator: "\n")
            logTrace("Choose \(selected)")

        case "RecruitTagsRefreshed":
            guard let count: Int = try? info.details["count"] else {
                return
            }
            logTrace("Refreshed \(count)")

        case "RecruitNoPermit":
            guard let shouldContinue: Bool = try? info.details["continue"] else {
                return
            }
            if shouldContinue {
                logTrace("ContinueRefresh")
            } else {
                logTrace("NoRecruitmentPermit")
            }

        case "NotEnoughStaff":
            logError("NotEnoughStaff")

        case "CreditFullOnlyBuyDiscount":
            guard let credit: Int = try? info.details["credit"] else {
                return
            }
            logTrace("CreditFullOnlyBuyDiscount \(credit)")

        case "AccountSwitch":
            let accountName: String = (try? info.details["account_name"]) ?? ""
            logTrace("AccountSwitch \(accountName)")

        case "StageInfo":
            guard let name: String = try? info.details["name"] else {
                return
            }
            logTrace("StartCombat \(name)")
        // TODO: Align delayed roguelike-abort state.

        case "StageInfoError":
            logError("StageInfoError")
        // TODO: Align log-card splitting and screenshot updates.

        case "BattleFormation":
            let formation: [String] = (try? info.details["formation"]) ?? []
            logTrace("BattleFormation \(formation.joined(separator: ", "))")
        // TODO: Localize operator names.

        case "BattleFormationParseFailed":
            logTrace("BattleFormationParseFailed")

        case "BattleFormationSelected":
            let selected: String = (try? info.details["selected"]) ?? ""
            let groupName: String? = try? info.details["group_name"]
            let displayName = groupName.map { "\($0) => \(selected)" } ?? selected
            logTrace("BattleFormationSelected \(displayName)")
        // TODO: Localize operator names.

        case "BattleFormationOperUnavailable":
            let operName: String = (try? info.details["oper_name"]) ?? ""
            let requirementType: String = (try? info.details["requirement_type"]) ?? "Unknown Type"
            logError("BattleFormationOperUnavailable \(operName) \(requirementType)")
        // TODO: Track ignored requirements and localize names/types. Use warning when requirements are ignored.

        case "CopilotAction":
            guard let action = CopilotActionDetails(json: info.details, context: info.what) else {
                return
            }
            if let doc = action.doc, !doc.isEmpty {
                logTrace("\(doc)")
            }
            logTrace("CurrentSteps \(action.action) \(action.target ?? "")")
            if let elapsedTime = action.elapsed_time, elapsedTime >= 0 {
                logTrace("ElapsedTime \(elapsedTime)")
            }
        // TODO: Apply doc_color and localize action/operator names.

        case "CopilotListLoadTaskFileSuccess":
            guard let file = CopilotFileDetails(json: info.details, context: info.what) else {
                return
            }
            logTrace("Parse \(file.file_name)[\(file.stage_name)] Success")
        // TODO: Store the current Copilot ID and reset ignored-requirement state.

        case "SSSStage":
            guard let stage: String = try? info.details["stage"] else {
                return
            }
            logInfo("CurrentStage \(stage)")

        case "SSSSettlement":
            if let why = info.why {
                logInfo("\(why)")
            }

        case "SSSGamePass":
            logRare("SSSGamePass")

        case "UnsupportedLevel":
            let level: JSON = (try? info.details["level"]) ?? .null
            logError("UnsupportedLevel \(String(describing: level))")
        // TODO: Trigger resource update and reload.

        case "CustomInfrastRoomGroupsMatch":
            guard let group: String = try? info.details["group"] else {
                return
            }
            logTrace("RoomGroupsMatch \(group)")

        case "CustomInfrastRoomGroupsMatchFailed":
            guard let groups: [String] = try? info.details["groups"] else {
                return
            }
            logTrace("RoomGroupsMatchFailed \(groups.joined(separator: ", "))")

        case "CustomInfrastRoomOperators":
            let names: [String] = (try? info.details["names"]) ?? []
            logTrace("RoomOperators \(names.joined(separator: ", "))")
        // TODO: Localize operator names.

        case "InfrastTrainingIdle":
            logTrace("TrainingIdle")

        case "InfrastTrainingCompleted", "InfrastTrainingTimeLeft":
            let operatorName: String = (try? info.details["operator"]) ?? "UnKnown"
            let skill: String = (try? info.details["skill"]) ?? "UnKnown"
            let level: Int = (try? info.details["level"]) ?? -1
            let trainingLevel = LocalizedStringResource("TrainingLevel")
            if info.what == "InfrastTrainingCompleted" {
                let trainingCompleted = LocalizedStringResource("TrainingCompleted")
                logInfo("[\(operatorName)] \(skill)\n\(trainingLevel): \(level) \(trainingCompleted)")
            } else {
                let time: String = (try? info.details["time"]) ?? "Unknown"
                let trainingTimeLeft = LocalizedStringResource("TrainingTimeLeft")
                logInfo("[\(operatorName)] \(skill)\n\(trainingLevel): \(level)\n\(trainingTimeLeft): \(time)")
            }
        // TODO: Localize operator names.

        case "ReclamationReport":
            let totalBadges: Int = (try? info.details["total_badges"]) ?? -1
            let badges: Int = (try? info.details["badges"]) ?? -1
            let totalConstructionPoints: Int = (try? info.details["total_construction_points"]) ?? -1
            let constructionPoints: Int = (try? info.details["construction_points"]) ?? -1
            let algorithmFinish = LocalizedStringResource("AlgorithmFinish")
            let algorithmBadge = LocalizedStringResource("AlgorithmBadge")
            let algorithmConstructionPoint = LocalizedStringResource("AlgorithmConstructionPoint")
            logTrace(
                "\(algorithmFinish)\n\(algorithmBadge): \(totalBadges)(+\(badges))\n\(algorithmConstructionPoint): \(totalConstructionPoints)(+\(constructionPoints))"
            )

        case "ReclamationProcedureStart":
            guard let times: Int = try? info.details["times"] else {
                return
            }
            logInfo("MissionStart \(times)")

        case "ReclamationSmeltGold":
            guard let times: Int = try? info.details["times"] else {
                return
            }
            logTrace("AlgorithmDoneSmeltGold \(times)")

        case "RoguelikeInvestmentReachFull":
            logInfo("RoguelikeInvestmentReachFull")

        case "RoguelikeInvestmentReachLimit":
            guard let limit: Int = try? info.details["limit"] else {
                return
            }
            logInfo("RoguelikeInvestmentReachLimit \(limit)")

        case "RoguelikeInvestment":
            guard let investment = RoguelikeInvestmentDetails(json: info.details, context: info.what) else {
                return
            }
            logInfo("RoguelikeInvestment \(investment.count) \(investment.total) \(investment.deposit)")

        case "RoguelikeSettlement":
            guard let settlement = RoguelikeSettlementDetails(json: info.details, context: info.what) else {
                return
            }
            logTrace(
                "RoguelikeSettlement \(settlement.game_pass ? "✓" : "✗") \(settlement.floor.map(String.init) ?? "") \(settlement.step.map(String.init) ?? "") \(settlement.combat.map(String.init) ?? "") \(settlement.emergency.map(String.init) ?? "") \(settlement.boss.map(String.init) ?? "") \(settlement.recruit.map(String.init) ?? "") \(settlement.collection.map(String.init) ?? "") \(settlement.difficulty.map(String.init) ?? "") \(settlement.score.map(String.init) ?? "") \(settlement.exp ?? "") \(settlement.skill ?? "")"
            )
        // TODO: Apply the selected theme's difficulty validation/OCR correction and update the
        // screenshot card.

        case "RoguelikeCombatEnd":
            // TODO: Clear the delayed-abort/in-combat state after Roguelike combat.
            break

        case "RoguelikeEvent":
            guard let name: String = try? info.details["name"] else {
                return
            }
            logInfo("RoguelikeEvent \(name)")

        case "RoguelikeEncounterOptions":
            let options: [RoguelikeEncounterOptionDetails] = (try? info.details["options"]) ?? []
            let optionLines = options.map { option in
                let resource: LocalizedStringResource
                if option.enabled {
                    resource = LocalizedStringResource("RoguelikeEncounterEnabledOption \(option.text)")
                } else {
                    resource = LocalizedStringResource("RoguelikeEncounterDisabledOption \(option.text)")
                }
                return String(localized: resource)
            }.joined(separator: "\n")
            let optionsTitle = LocalizedStringResource("RoguelikeEncounterOptions \(options.count)")
            if optionLines.isEmpty {
                logInfo("\(optionsTitle)")
            } else {
                logInfo("\(optionsTitle)\n\(optionLines)")
            }
        // TODO: Update the screenshot card.

        case "BlackFlowRoutingDecision":
            guard let decision = BlackFlowRoutingDecisionDetails(json: info.details, context: info.what) else {
                return
            }
            logInfo(
                "BlackFlowRoutingDecision \(decision.floor) \(decision.action_points_before) \(decision.action_points_after) \(decision.movement) \(decision.node_name ?? decision.node_type) \(decision.safety_margin)"
            )
            logInfo("BlackFlowRoutingReason \(decision.reason_category) \(decision.reason_detail ?? "")")
        // TODO: Localize BlackFlow movement, node type, reason category, and reason detail values.

        case "BlackFlowRoutingWarning":
            let code: String = (try? info.details["code"]) ?? ""
            switch code {
            case "map_rebuild_failed": logWarn("BlackFlowWarningMapRebuildFailed")
            case "page_recovery_failed": logWarn("BlackFlowWarningPageRecoveryFailed")
            case "preview_cost_changed": logWarn("BlackFlowWarningPreviewCostChanged")
            case "route_blocked": logWarn("BlackFlowWarningRouteBlocked")
            case "insufficient_action_points": logWarn("BlackFlowWarningInsufficientActionPoints")
            case "target_state_changed": logWarn("BlackFlowWarningTargetStateChanged")
            case "target_unreachable": logWarn("BlackFlowWarningTargetUnreachable")
            case "inferred_edge_selected": logWarn("BlackFlowWarningInferredEdge")
            case "post_move_mismatch": logWarn("BlackFlowWarningPostMoveMismatch")
            case "identity_conflict": logWarn("BlackFlowWarningIdentityConflict")
            default: logWarn("BlackFlowWarningUnknown")
            }

        case "BlackFlowMilestoneChanged":
            let status: String = (try? info.details["status"]) ?? ""
            let milestoneId: String = (try? info.details["milestone_id"]) ?? ""
            if status != "inactive" {
                logInfo("BlackFlowMilestoneChanged \(milestoneId) \(status)")
            }
        // TODO: Localize BlackFlow milestone identifiers and status values.

        case "BlackFlowStrategyStarted":
            let profile: String = (try? info.details["profile"]) ?? ""
            logInfo("BlackFlowStrategyStarted \(profile)")
        // TODO: Localize the BlackFlow profile value.

        case "BlackFlowStrategyResult":
            let outcome: String = (try? info.details["outcome"]) ?? ""
            let terminationReason: String = (try? info.details["termination_reason"]) ?? ""
            let succeeded: Bool = (try? info.details["succeeded"]) ?? false
            if succeeded {
                logInfo("BlackFlowStrategyResult \(outcome) \(terminationReason)")
            } else {
                logWarn("BlackFlowStrategyResult \(outcome) \(terminationReason)")
            }
        // TODO: Localize the outcome and termination reason.

        case "BoskyPassageNode":
            guard let nodeType: String = try? info.details["node_type"] else {
                return
            }
            switch nodeType {
            case "Omissions": logInfo("BoskyOmissions")
            case "Legend": logInfo("BoskyLegend")
            case "OldShop": logInfo("BoskyOldShop")
            case "YiTrader": logInfo("BoskyYiTrader")
            case "Scheme": logInfo("BoskyScheme")
            case "Playtime": logInfo("BoskyPlaytime")
            case "Doubts": logInfo("BoskyDoubts")
            case "Disaster": logWarn("BoskyDisaster")
            default: logInfo("\(nodeType)")
            }

        case "RoguelikeCoppersRecognitionError":
            let recognizedName: String = (try? info.details["recognized_name"]) ?? "Unknown"
            logError("RoguelikeCoppersRecognitionError \(recognizedName)")

        case "RoguelikeCoppersExchangeInfo":
            let toDiscard: String = (try? info.details["to_discard"]) ?? "Unknown"
            let toPickup: String = (try? info.details["to_pickup"]) ?? "Unknown"
            logInfo("RoguelikeCoppersExchange \(toDiscard) \(toPickup)")

        case "EncounterOcrError":
            logError("EncounterOcrError")

        case "RoguelikeJieGardenTargetFound":
            let targetSubtype: String = (try? info.details["target_subtype"]) ?? "Unknown"
            let targetName: String
            switch targetSubtype {
            case "Ling": targetName = String(localized: "RoguelikePlaytimeLing")
            case "Shu": targetName = String(localized: "RoguelikePlaytimeShu")
            case "Nian": targetName = String(localized: "RoguelikePlaytimeNian")
            default: targetName = targetSubtype
            }
            logInfo("RoguelikeJieGardenTargetFound \(targetName)")

        case "FoldartalGainOcrNextLevel":
            let foldartal: String = (try? info.details["foldartal"]) ?? ""
            logTrace("FoldartalGainOcrNextLevel \(foldartal)")

        case "MonthlySquadCompleted":
            logRare("MonthlySquadCompleted")

        case "DeepExplorationCompleted":
            logRare("DeepExplorationCompleted")

        case "RoguelikeCollapsalParadigms":
            guard let deepenOrWeaken: Int = try? info.details["deepen_or_weaken"] else {
                return
            }
            let current: String = (try? info.details["cur"]) ?? "UnKnown"
            let previous: String = (try? info.details["prev"]) ?? "UnKnown"
            if deepenOrWeaken == 1, previous.isEmpty {
                logInfo("RoguelikeGainParadigm \(current)")
            } else if deepenOrWeaken == 1 {
                logInfo("RoguelikeDeepenParadigm \(current) \(previous)")
            } else if deepenOrWeaken == -1, current.isEmpty {
                logInfo("RoguelikeLoseParadigm \("") \(previous)")
            } else if deepenOrWeaken == -1 {
                logInfo("RoguelikeWeakenParadigm \(current) \(previous)")
            }

        case "UseMedicine":
            guard let medicine = UseMedicineDetails(json: info.details, context: info.what) else {
                return
            }
            if medicine.is_expiring {
                expiringMedicineUsedTimes += medicine.count
                logInfo("ExpiringMedicineUsed \("--") \(expiringMedicineUsedTimes) \(medicine.count)")
            } else {
                medicineUsedTimes += medicine.count
                logInfo("MedicineUsed \(medicineUsedTimes) \(medicine.count)")
            }
            for item in medicine.medicines ?? [] {
                logInfo("UseMedicine.MedicineInfo \(item.use) \(item.inventory)")
            }
        // TODO: Calculate expiring-medicine hours from task settings.

        case "SanityBeforeStage":
            guard let currentSanity: Int = try? info.details["current_sanity"] else {
                return
            }
            curSanityBeforeFight = currentSanity
        // TODO: Store the complete sanity report used by WPF.

        case "FightTimes":
            guard let currentSanityCost: Int = try? info.details["sanity_cost"] else {
                return
            }
            sanityCost = currentSanityCost
        // TODO: Store the complete fight report and unused-run warning.

        case "StageQueueUnableToAgent":
            guard let stageCode: String = try? info.details["stage_code"] else {
                return
            }
            logInfo("StageQueue \(stageCode) \(String(localized: "UnableToAgent"))")

        case "StageQueueMissionCompleted":
            guard let stageCode: String = try? info.details["stage_code"],
                let stars: Int = try? info.details["stars"]
            else {
                return
            }
            logInfo("StageQueue \(stageCode) \(stars)")

        case "PixelPaintProgress":
            let done: Int = (try? info.details["done"]) ?? 0
            let total: Int = (try? info.details["total"]) ?? 0
            if done >= total, total > 0 {
                logInfo("MiniGame@PixelPaint@DoneLog")
            } else {
                logTrace("MiniGame@PixelPaint@ProgressLog \(done) \(total)")
            }
        // TODO: Apply the current palette color to the progress log.

        case "Finished" where info.taskchain == "VideoRecognition":
            guard let filename: String = try? info.details["filename"] else {
                return
            }
            videoRecoginition = URL(fileURLWithPath: filename)
            logInfo("Save to: \(filename)")
        // TODO: Reveal the generated file in Finder.

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
    /// 实例已销毁
    fileprivate static let Destroyed = 5

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

    /// 上报请求
    fileprivate static let ReportRequest = 30000
}

// MARK: - Convenience Methods

extension MAAViewModel {
    fileprivate static let SubTaskStopped = 20004
}

// MARK: - Convenience Methods

extension MAAViewModel {
    func logTrace(_ resource: LocalizedStringResource) {
        writeLog(color: .trace, resource)
    }

    func logInfo(_ resource: LocalizedStringResource) {
        writeLog(color: .info, resource)
    }

    func logWarn(_ resource: LocalizedStringResource) {
        writeLog(color: .warning, resource)
    }

    func logRare(_ resource: LocalizedStringResource) {
        writeLog(color: .rare, resource)
    }

    func logError(_ resource: LocalizedStringResource) {
        writeLog(color: .error, resource)
    }

    private func writeLog(color: MAALog.LogColor, _ resource: LocalizedStringResource) {
        let content = String(localized: resource)
        let entry = MAALog(date: Date(), content: content, color: color)
        logStore?.appendLog(entry)
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
