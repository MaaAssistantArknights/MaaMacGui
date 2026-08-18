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

private let blackFlowWarningKeys = [
    "map_rebuild_failed": "BlackFlowWarningMapRebuildFailed",
    "page_recovery_failed": "BlackFlowWarningPageRecoveryFailed",
    "preview_cost_changed": "BlackFlowWarningPreviewCostChanged",
    "route_blocked": "BlackFlowWarningRouteBlocked",
    "insufficient_action_points": "BlackFlowWarningInsufficientActionPoints",
    "target_state_changed": "BlackFlowWarningTargetStateChanged",
    "target_unreachable": "BlackFlowWarningTargetUnreachable",
    "inferred_edge_selected": "BlackFlowWarningInferredEdge",
    "post_move_mismatch": "BlackFlowWarningPostMoveMismatch",
    "identity_conflict": "BlackFlowWarningIdentityConflict",
]

private let blackFlowNodeKeys = [
    "empty": "BlackFlowNodeEmpty",
    "battle_normal": "BlackFlowNodeCombat",
    "combat": "BlackFlowNodeCombat",
    "battle_elite": "BlackFlowNodeEmergencyCombat",
    "emergency_combat": "BlackFlowNodeEmergencyCombat",
    "battle_boss": "BlackFlowNodeBoss",
    "boss": "BlackFlowNodeBoss",
    "shop": "BlackFlowNodeBattleShop",
    "battle_shop": "BlackFlowNodeBattleShop",
    "scrap_shop": "BlackFlowNodeScrapShop",
    "incident": "BlackFlowNodeEncounter",
    "encounter": "BlackFlowNodeEncounter",
    "hide_invisible": "BlackFlowNodeMysteriousPresage",
    "mysterious_presage": "BlackFlowNodeMysteriousPresage",
    "hide_battle": "BlackFlowNodeFerociousPresage",
    "ferocious_presage": "BlackFlowNodeFerociousPresage",
    "expedition": "BlackFlowNodeScout",
    "scout": "BlackFlowNodeScout",
    "battle_savage": "BlackFlowNodeResidentStronghold",
    "duel": "BlackFlowNodeDuel",
    "face_off": "BlackFlowNodeDuel",
    "employ": "BlackFlowNodeEmergencyAid",
    "emergency_aid": "BlackFlowNodeEmergencyAid",
    "rest": "BlackFlowNodeRest",
    "light": "BlackFlowNodeFeatherPoint",
    "feather_point": "BlackFlowNodeFeatherPoint",
    "door": "BlackFlowNodeWindingPassage",
    "winding_passage": "BlackFlowNodeWindingPassage",
    "sacrifice": "BlackFlowNodeSacrifice",
    "wish": "BlackFlowNodeWish",
    "portal": "BlackFlowNodeBoskyPassage",
    "bosky_passage": "BlackFlowNodeBoskyPassage",
    "resident_stronghold": "BlackFlowNodeResidentStronghold",
    "final": "BlackFlowNodeFinal",
    "fate": "BlackFlowNodeFate",
    "evacuate": "BlackFlowNodeEvacuate",
    "teleporter": "BlackFlowNodeTeleporter",
    "unclassified": "BlackFlowNodeUnknown",
    "other": "BlackFlowNodeOther",
]

private let blackFlowReasonKeys = [
    "mandatory_goal": "BlackFlowReasonMandatoryGoal",
    "resource_reserve": "BlackFlowReasonResourceReserve",
    "preferred_goal": "BlackFlowReasonPreferredGoal",
    "development": "BlackFlowReasonDevelopment",
    "risk_avoidance": "BlackFlowReasonRiskAvoidance",
    "safety_fallback": "BlackFlowReasonSafetyFallback",
]

private let blackFlowMilestoneStatusKeys = [
    "available": "BlackFlowMilestoneStatusAvailable",
    "satisfied": "BlackFlowMilestoneStatusSatisfied",
    "missed": "BlackFlowMilestoneStatusMissed",
    "impossible": "BlackFlowMilestoneStatusImpossible",
]

private let blackFlowOutcomeKeys = [
    "investment_completed": "BlackFlowOutcomeInvestmentCompleted",
    "investment_missed": "BlackFlowOutcomeInvestmentMissed",
    "burn_completed": "BlackFlowOutcomeFloor3RouteCompleted",
    "baby_cultivation_completed": "BlackFlowOutcomeBabyCultivationCompleted",
    "baby_cultivation_target_missed": "BlackFlowOutcomeBabyCultivationTargetMissed",
    "ending_prerequisite_failed": "BlackFlowOutcomeEndingPrerequisiteFailed",
    "strategy_completed": "BlackFlowOutcomeStrategyCompleted",
    "page_recovery_failed": "BlackFlowOutcomePageRecoveryFailed",
    "ending2_completed": "BlackFlowOutcomeEnding2Completed",
    "ending3_completed": "BlackFlowOutcomeEnding3Completed",
    "ending2_prerequisite_failed": "BlackFlowOutcomeEnding2PrerequisiteFailed",
    "ending3_prerequisite_failed": "BlackFlowOutcomeEnding3PrerequisiteFailed",
    "baby_cultivation_unfinished": "BlackFlowOutcomeBabyCultivationUnfinished",
    "task_event_failed": "BlackFlowOutcomeTaskEventFailed",
    "perception_port_missing": "BlackFlowOutcomePerceptionPortMissing",
    "map_rebuild_failed": "BlackFlowOutcomeMapRebuildFailed",
    "planning_failed": "BlackFlowOutcomePlanningFailed",
    "transaction_proposal_failed": "BlackFlowOutcomeTransactionProposalFailed",
    "move_preview_failed": "BlackFlowOutcomeMovePreviewFailed",
    "move_preview_rejected": "BlackFlowOutcomeMovePreviewRejected",
    "move_confirmation_failed": "BlackFlowOutcomeMoveConfirmationFailed",
    "post_move_validation_failed": "BlackFlowOutcomePostMoveValidationFailed",
    "planning_retry_exhausted": "BlackFlowOutcomePlanningRetryExhausted",
    "state_machine_dead_end": "BlackFlowOutcomeStateMachineDeadEnd",
    "map_recovery_exhausted": "BlackFlowOutcomeMapRecoveryExhausted",
    "floor_recognition_failed": "BlackFlowOutcomeFloorRecognitionFailed",
    "movement_inventory_observation_failed": "BlackFlowOutcomeMovementInventoryFailed",
    "movement_selection_failed": "BlackFlowOutcomeMovementSelectionFailed",
    "node_dispatch_failed": "BlackFlowOutcomeNodeDispatchFailed",
    "node_result_failed": "BlackFlowOutcomeNodeResultFailed",
    "internal_failure": "BlackFlowOutcomeInternalFailure",
]

private let blackFlowTerminationKeys = [
    "investment_finished": "BlackFlowTerminationInvestmentFinished",
    "investment_shop_window_closed": "BlackFlowTerminationInvestmentShopWindowClosed",
    "third_floor_reached": "BlackFlowTerminationFloor3Reached",
    "cultivation_result_reported": "BlackFlowTerminationCultivationReported",
    "cultivation_target_obtained": "BlackFlowTerminationCultivationTargetObtained",
    "cultivation_target_not_obtained": "BlackFlowTerminationCultivationTargetNotObtained",
    "floor1_shop_has_no_seed": "BlackFlowTerminationFloor1ShopNoSeed",
    "mandatory_prerequisite_missed": "BlackFlowTerminationMandatoryPrerequisiteMissed",
    "strategy_terminal_reached": "BlackFlowTerminationStrategyTerminalReached",
    "node_page_recovery_failed": "BlackFlowTerminationNodePageRecoveryFailed",
    "ending2_completed": "BlackFlowTerminationEnding2Completed",
    "ending3_completed": "BlackFlowTerminationEnding3Completed",
    "ending2_prerequisite_missing": "BlackFlowTerminationEnding2PrerequisiteMissing",
    "ending3_relic_missing": "BlackFlowTerminationEnding3RelicMissing",
    "no_bosky_passage": "BlackFlowTerminationNoBoskyPassage",
    "action_points_exhausted_before_cultivation": "BlackFlowTerminationActionPointsExhaustedBeforeCultivation",
    "scrap_shop_never_reached": "BlackFlowTerminationScrapShopNeverReached",
    "recovery_port_unavailable": "BlackFlowTerminationRecoveryPortUnavailable",
    "perception_port_unavailable": "BlackFlowTerminationPerceptionPortUnavailable",
    "map_rebuild_failed_twice": "BlackFlowTerminationMapRebuildFailedTwice",
    "planning_retry_exhausted": "BlackFlowTerminationPlanningRetryExhausted",
]

private let localizedBlackFlowKeys: Set<String> = Set(
    [
        "BlackFlowRuleAvoidEmptyScrapShop",
        "BlackFlowRulePreserveWhiteModelBird",
        "BlackFlowRuleTriggerBossProcessingBonus",
        "BlackFlowRuleExitWhenRequired",
        "BlackFlowRuleEnding1AvoidLateCombat",
        "BlackFlowRuleBabyUseProcessingItemForFloor1Shop",
        "BlackFlowRuleBabyWalkAfterFloor1Shop",
        "BlackFlowRuleBabyDelayExitBeforeFloor3",
        "BlackFlowRuleBabyExitBeforeFloor3WhenRequired",
        "BlackFlowRuleBabyAvoidCombat",
        "BlackFlowRuleLightRevealsThree",
        "BlackFlowRuleInvestmentKeepShortWalk",
        "BlackFlowRuleInvestmentUseM11ForDirectShop",
        "BlackFlowRuleBurnRequireShopWhenFlightGuaranteed",
        "BlackFlowRuleBurnRequireFlightOnFloor2",
        "BlackFlowMilestoneEnding1Floor1Battles",
        "BlackFlowMilestoneEnding1Floor1Hidden",
        "BlackFlowMilestoneEnding1Floor2Expedition",
        "BlackFlowMilestoneEnding1Floor2ScrapShop",
        "BlackFlowMilestoneEnding1Floor2Hidden",
        "BlackFlowMilestoneEnding1Floor2Employ",
        "BlackFlowMilestoneEnding1Floor2Light",
        "BlackFlowMilestoneEnding1Floor2Wish",
        "BlackFlowMilestoneEnding1LateDuel",
        "BlackFlowMilestoneEnding1LateExpedition",
        "BlackFlowMilestoneEnding1LateScrapShop",
        "BlackFlowMilestoneEnding1LateEmploy",
        "BlackFlowMilestoneEnding1LateHidden",
        "BlackFlowMilestoneEnding1LateIncident",
        "BlackFlowMilestoneEnding1LateCombat",
        "BlackFlowMilestoneEnding1LateLight",
        "BlackFlowMilestoneEnding1LateWish",
        "BlackFlowMilestoneInvestmentShop",
        "BlackFlowMilestoneBurnFloor1Shop",
        "BlackFlowMilestoneBurnFloor1Final",
        "BlackFlowMilestoneBurnFloor2Final",
        "BlackFlowMilestoneBabyCheckSeedShop",
        "BlackFlowMilestoneBabyCultivateScrapShop",
        "BlackFlowMilestoneBabyExploreHidden",
        "BlackFlowMilestoneBabyVisitIncident",
        "BlackFlowMilestoneBabyVisitLight",
        "BlackFlowMilestoneBabyFloor2Shops",
        "BlackFlowMilestoneBabyFloor3Shops",
        "BlackFlowMilestoneEnding2SandtableA",
        "BlackFlowMilestoneEnding2SandtableB",
        "BlackFlowMilestoneEnding2Fate",
        "BlackFlowMilestoneEnding3DeviceOption2",
        "BlackFlowMilestoneEnding3Relics",
        "BlackFlowMilestoneEnding3Floor5Boss",
        "BlackFlowMilestoneEnding3Floor6",
    ]
)

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
            logTrace("AllTasksComplete")
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

            case "StageCombatOpsEnter":
                logTrace("CombatOps")

            case "StageEmergencyOps":
                logTrace("EmergencyOps")

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
                allDrops.append(String(localized: "NoDrop"))
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
        case "BlackFlowRoutingDecision":
            let floor = subTaskDetails["floor"].int ?? 0
            let before = subTaskDetails["action_points_before"].int ?? 0
            let after = subTaskDetails["action_points_after"].int ?? 0
            let movement = subTaskDetails["movement"].string == "walk"
                ? localizedBlackFlow("BlackFlowMovementWalk")
                : localizedBlackFlow("BlackFlowMovementProcessing")
            let nodeName = subTaskDetails["node_name"].string.flatMap { $0.isEmpty ? nil : $0 }
                ?? localizedBlackFlowNode(subTaskDetails["node_type"].string)
            let category = localizedBlackFlowReasonCategory(subTaskDetails["reason_category"].string)
            let reason = localizedBlackFlowDecisionDetail(subTaskDetails)
            let route = localizedBlackFlowFormat(
                "BlackFlowRoutingDecision",
                defaultValue: "第 \(floor) 层｜行动力 \(before)→\(after)｜\(movement)至 \(nodeName)｜安全余量 \(subTaskDetails["safety_margin"].int ?? 0)",
                arguments: [
                    "\(floor)", "\(before)", "\(after)", movement, nodeName,
                    "\(subTaskDetails["safety_margin"].int ?? 0)",
                ])
            let reasonLine = localizedBlackFlowFormat(
                "BlackFlowRoutingReason",
                defaultValue: "原因：\(category)｜说明：\(reason)",
                arguments: [category, reason])
            logLocalizedInfo("\(route)\n\(reasonLine)")

        case "BlackFlowRoutingWarning":
            let key = blackFlowWarningKeys[subTaskDetails["code"].string ?? ""] ?? "BlackFlowWarningUnknown"
            logLocalizedWarning(localizedBlackFlow(key))

        case "BlackFlowMilestoneChanged":
            guard subTaskDetails["status"].string != "inactive" else {
                break
            }
            let milestone = localizedBlackFlowIdentifier(
                prefix: "BlackFlowMilestone",
                identifier: subTaskDetails["milestone_id"].string,
                fallback: "BlackFlowMilestoneUnknown")
            let status = localizedBlackFlowMilestoneStatus(subTaskDetails["status"].string)
            logLocalizedInfo(
                localizedBlackFlowFormat(
                    "BlackFlowMilestoneChanged",
                    defaultValue: "阶段目标：\(milestone)（\(status)）",
                    arguments: [milestone, status]))

        case "BlackFlowStrategyStarted":
            let profile = localizedBlackFlowProfile(subTaskDetails["profile"].string)
            logLocalizedInfo(
                localizedBlackFlowFormat(
                    "BlackFlowStrategyStarted",
                    defaultValue: "黑流策略已启动：\(profile)",
                    arguments: [profile]))

        case "BlackFlowStrategyResult":
            let outcome = localizedBlackFlowOutcome(subTaskDetails["outcome"].string)
            let reason = localizedBlackFlowTerminationReason(subTaskDetails["termination_reason"].string)
            let message = localizedBlackFlowFormat(
                "BlackFlowStrategyResult",
                defaultValue: "肉鸽策略结束：\(outcome)（\(reason)）",
                arguments: [outcome, reason])
            if subTaskDetails["succeeded"].bool == true {
                logLocalizedInfo(message)
            } else {
                logLocalizedWarning(message)
            }

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

    private func logLocalizedInfo(_ content: String) {
        writeLog(color: .info, content: content)
    }

    private func logLocalizedWarning(_ content: String) {
        writeLog(color: .warning, content: content)
    }

    private func writeLog(color: MAALog.LogColor, content: String) {
        let entry = MAALog(date: Date(), content: content, color: color)
        logs.append(entry)
        fileLogger.write(entry)
    }

    private func localizedBlackFlow(_ key: String) -> String {
        String(localized: String.LocalizationValue(stringLiteral: key))
    }

    private func localizedBlackFlowFormat(_ key: String, defaultValue: String, arguments: [String]) -> String {
        var localized = localizedBlackFlow(key)
        if localized == key {
            localized = defaultValue
        }
        for (index, argument) in arguments.enumerated() {
            localized = localized.replacingOccurrences(of: "{\(index)}", with: argument)
        }
        return localized
    }

    private func localizedBlackFlowProfile(_ profile: String?) -> String {
        switch profile {
        case "investment":
            return localizedBlackFlow("RoguelikeStrategyBlackFlowInvestment")
        case "burn", "burn_with_investment":
            return localizedBlackFlow("RoguelikeStrategyBlackFlowExp")
        case "baby_animal":
            return localizedBlackFlow("RoguelikeStrategyBlackFlowBabyAnimal")
        default:
            return localizedBlackFlow("BlackFlowStrategyUnknown")
        }
    }

    private func localizedBlackFlowIdentifier(prefix: String, identifier: String?, fallback: String) -> String {
        guard let identifier, !identifier.isEmpty else {
            return localizedBlackFlow(fallback)
        }
        let suffix = identifier.split(separator: "_").map {
            $0.prefix(1).uppercased() + $0.dropFirst()
        }.joined()
        let key = prefix + suffix
        return localizedBlackFlowKeys.contains(key) ? localizedBlackFlow(key) : localizedBlackFlow(fallback)
    }

    private func localizedBlackFlowDecisionDetail(_ details: JSON) -> String {
        if let rule = details["decisive_rule_id"].string, !rule.isEmpty {
            return localizedBlackFlowIdentifier(
                prefix: "BlackFlowRule",
                identifier: rule,
                fallback: "BlackFlowDecisionDetailUnknown")
        }
        if let milestone = details["decisive_milestone_id"].string, !milestone.isEmpty {
            return localizedBlackFlowIdentifier(
                prefix: "BlackFlowMilestone",
                identifier: milestone,
                fallback: "BlackFlowDecisionDetailUnknown")
        }
        switch details["reason_detail"].string {
        case "selected unclassified frontier probe":
            return localizedBlackFlow("BlackFlowDecisionProbeUnknownNode")
        case "selected by lexicographic policy order":
            return localizedBlackFlow("BlackFlowDecisionPolicyOrder")
        default:
            return localizedBlackFlow("BlackFlowDecisionDetailUnknown")
        }
    }

    private func localizedBlackFlowNode(_ nodeType: String?) -> String {
        let key = blackFlowNodeKeys[nodeType ?? ""] ?? "BlackFlowNodeUnknown"
        return localizedBlackFlow(key)
    }

    private func localizedBlackFlowReasonCategory(_ category: String?) -> String {
        let key = blackFlowReasonKeys[category ?? ""] ?? "BlackFlowReasonTieBreak"
        return localizedBlackFlow(key)
    }

    private func localizedBlackFlowMilestoneStatus(_ status: String?) -> String {
        let key = blackFlowMilestoneStatusKeys[status ?? ""] ?? "BlackFlowMilestoneStatusUnknown"
        return localizedBlackFlow(key)
    }

    private func localizedBlackFlowOutcome(_ outcome: String?) -> String {
        let key = blackFlowOutcomeKeys[outcome ?? ""] ?? "BlackFlowOutcomeUnknown"
        return localizedBlackFlow(key)
    }

    private func localizedBlackFlowTerminationReason(_ reason: String?) -> String {
        let key = blackFlowTerminationKeys[reason ?? ""] ?? "BlackFlowTerminationUnknown"
        return localizedBlackFlow(key)
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
