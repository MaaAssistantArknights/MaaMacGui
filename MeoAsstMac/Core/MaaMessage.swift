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

private func L(_ resource: LocalizedStringResource) -> String {
    String(localized: resource)
}

private func l(_ key: String, value: String? = nil) -> String {
    Bundle.main.localizedString(forKey: key, value: value, table: nil)
}

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

extension Decodable {
    fileprivate init?(json: JSON, context: String) {
        do {
            let data = try json.serialize()
            self = try JSONDecoder().decode(Self.self, from: data)
        } catch {
            logger.error("Failed to parse \(context): \(error); details: \(json)")
            return nil
        }
    }
}

// MARK: - Process Message

extension MAAViewModel {
    func processMessage(_ message: MaaMessage) {
        switch message.code {
        case .InternalError:
            // WPF retains this callback but currently performs no operation.
            break

        case .InitFailed:
            // Core currently does not emit this callback.
            // TODO: (Dialog) Show the initialization error dialog.
            // TODO: (ApplicationLifecycle) Terminate the app after initialization fails.
            break

        case .ConnectionInfo:
            processConnectionInfo(message)

        case .AsyncCallInfo:
            // MAAHandle consumes async-call callbacks before they reach the ViewModel.
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
            // TODO: (NetworkReport) Perform the HTTP data-reporting request provided by Core.
            break

        default:
            logger.warning("Unhandled MaaMessage code: \(message.code)")
        }
    }
}

// MARK: - Process Connection

private func parseResolution(details: JSON) -> (width: Int, height: Int)? {
    guard let width: Int = try? details["details"]["width"],
        let height: Int = try? details["details"]["height"]
    else {
        return nil
    }
    return (width, height)
}

extension MAAViewModel {
    private func processConnectionInfo(_ message: MaaMessage) {
        let details = message.details
        guard let what: String = try? details["what"] else {
            return
        }

        switch what {
        case "Connected":
            // TODO: (ConnectionState) Store the connected ADB path and address, then clear the last connection error.
            if let address: String = try? details["details"]["address"] {
                logInfo("已连接至 \(address)")
            }

        case "UnsupportedResolution":
            // TODO: (ConnectionState) Mark the current connection as unavailable and retain the error message.
            if let (width, height) = parseResolution(details: details), width > 0, height > 0 {
                logError(.currentResolution(message: L(.resolutionNotSupported), width: width, height: height))
            } else {
                logError(.resolutionNotSupported)
            }

        case "ResolutionChanged":
            // TODO: (ConnectionState) Mark the invalidated connection as unavailable and retain the error message.
            if let (width, height) = parseResolution(details: details), width > 0, height > 0 {
                logError(.currentResolution(message: L(.resolutionChanged), width: width, height: height))
            } else {
                logError(.resolutionChanged)
            }

        case "ResolutionInfo":
            if let (width, height) = parseResolution(details: details) {
                if clientChannel == .YoStarEN, width != 1920 || height != 1080 {
                    logError(.resolutionInfoYoStarEN)
                }
            }

        case "MuMuExtrasInputStatus":
            // Not available on macOS
            break

        case "ResolutionError":
            // TODO: (ConnectionState) Mark the current connection as unavailable and retain the error message.
            logError(.resolutionAcquisitionFailure)

        case "Reconnecting":
            guard let times: Int = try? details["details"]["times"] else {
                return
            }
            logError(.tryToReconnect(times: times + 1))

        case "Reconnected":
            logTrace(.reconnectSuccess)

        case "Disconnect":
            // TODO: (ConnectionState) Mark the current connection as unavailable.
            logError(.reconnectFailed)
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
            logError(.screencapFailed)

        case "TouchModeNotAvailable":
            // TODO: (ConnectionState) Mark the current connection as unavailable.
            logError(.touchModeNotAvailable)

        case "FastestWayToScreencap":
            // TODO: (ConnectionState) Store the selected screencap method and its summary.
            // TODO: (Tooltip) Show alternative screencap methods and costs.
            guard let cost: Int = try? details["details"]["cost"],
                let method: String = try? details["details"]["method"]
            else {
                return
            }
            if cost > 400 {
                logWarn(.fastestWayToScreencap(cost: cost, method: method))
            } else {
                logTrace(.fastestWayToScreencap(cost: cost, method: method))
            }

        case "ScreencapCost":
            // TODO: (Achievement) Mirror WPF screenshot-performance achievement progress.
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
                logWarn(.fastestWayToScreencapErrorTip(average: average))
            case 400:
                logWarn(.fastestWayToScreencapWarningTip(average: average))
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
                logError(.emulatorFpsErrorTip(fps: fps))
            case ..<60:
                logWarn(.emulatorFpsWarningTip(fps: fps))
            default:
                if logStore?.hasPrintedFPSHighTip != true {
                    logWarn(.emulatorFpsHighTip(fps: fps))
                    logStore?.hasPrintedFPSHighTip = true
                }
            }

        case "UnsupportedPlayTools":
            logError("不支持此版本PlayCover")

        default:
            break
        }
    }
}

// MARK: - Process TaskChain

extension NewViewModel.SanityReport {
    fileprivate func fullRecoveryTime() -> Date? {
        guard let reportedAt else {
            return nil
        }
        let missingSanity = max(maximum - current, 0)
        return reportedAt.addingTimeInterval(TimeInterval(missingSanity * 6 * 60))
    }
}

@JSONRepresentable
private struct TaskChainMessage {
    let taskchain: String
    let taskid: Int32
}

extension MAAViewModel {
    private func processTaskChainMessage(_ message: MaaMessage) {
        if message.code == .AllTasksCompleted {
            // TODO: (LogCard) Update the all-tasks-completed log card.
            // TODO: (Notification) Show the all-tasks-completed notification.
            // TODO: (ExternalNotification) Send the all-tasks-completed event.
            // TODO: (Notification) Schedule the sanity-recovery notification.
            // TODO: (PostAction) Execute the configured completion action.
            // TODO: (ViewState) Show the April Fools completion animation when applicable.
            // TODO: (Notification) Show completion feedback for standalone Copilot tasks.
            // TODO: (Persistence) Record the credit-store easter-egg date when applicable.
            // TODO: (Dialog) Present the credit-store easter-egg dialog when applicable.
            // TODO: (ViewState) Apply the easter-egg language after confirmation.
            // TODO: (Achievement) Mirror WPF all-tasks-completed achievement progress.
            defer {
                resetStatus()
            }
            guard let ids: [Int32] = try? message.details["finished_tasks"] else {
                return
            }
            for id in ids {
                guard let task = dailyTask(coreID: id) else {
                    continue
                }
                if case .closedown = task {
                    continue
                }
                guard let start = logStore?.taskStartTime else {
                    break
                }
                let now = Date.now
                let duration = (start..<now).formatted(.timeDuration)
                let sanitySuffix: String
                if let recoveryTime = logStore?.sanityReport?.fullRecoveryTime() {
                    let recoveryDate = recoveryTime.formatted(date: .numeric, time: .shortened)
                    let remaining = (now..<max(now, recoveryTime)).formatted(.timeDuration)
                    sanitySuffix = "\n\(L(.sanityReport(date: recoveryDate, duration: remaining)))"
                } else {
                    sanitySuffix = ""
                }
                logTrace(.allTasksComplete(duration: duration, sanity: sanitySuffix))
                break
            }
            return
        }

        if message.code == .TaskChainStopped {
            resetStatus()
            logTrace(.stopped)
        }

        guard let info = TaskChainMessage(json: message.details, context: "TaskChain") else {
            return
        }

        if info.taskchain == "CloseDown" {
            // WPF retains this task-chain callback but currently performs no operation.
            return
        }

        if info.taskchain == "Recruit", message.code == .TaskChainError {
            // TODO: (Notification) Show the recruit-recognition error notification.
            // TODO: (ViewState) Show the recruit-recognition error in RecruitView.
            let resource = LocalizedStringResource.identifyTheMistakes
            _ = resource
        }

        let isCopilot = ["Copilot", "SSSCopilot"].contains(info.taskchain)

        let taskchainName: String
        if let task = MAATaskType(rawValue: info.taskchain) {
            taskchainName = task.description
        } else {
            taskchainName = l(info.taskchain)
        }

        switch message.code {
        case .TaskChainStopped:
            finishInfrastRotation(coreID: info.taskid, succeeded: false)
            if let id = taskID(coreID: info.taskid) {
                taskStatus[id] = .cancel
            }

        case .TaskChainError:
            finishInfrastRotation(coreID: info.taskid, succeeded: false)
            // TODO: (LogCard) Update the task-error log card.
            // TODO: (Screenshot) Fetch the latest screenshot for the error card.
            // TODO: (Tooltip) Use the error screenshot as the log tooltip.
            // TODO: (Notification) Show the task-error notification.
            // TODO: (ExternalNotification) Send the task-error event.
            // TODO: (Achievement) Record Copilot task errors.
            if let id = taskID(coreID: info.taskid) {
                taskStatus[id] = .failure
            }
            let error: String? = try? message.details["details"]["error"]
            if error == "OutOfMemory" {
                logError(.outOfMemoryError(name: taskchainName))
            } else {
                logError(.taskError(name: taskchainName))
            }
            if isCopilot {
                logError(.combatError)
            }

        case .TaskChainStart:
            updateInfrastAttempt(coreID: info.taskid, status: .running)
            // macOS task items do not currently support custom display names.
            // TODO: (ViewState) Switch the overlay log source for Copilot and daily tasks.
            if let id = taskID(coreID: info.taskid) {
                taskStatus[id] = .running
            }
            logTrace(.startTask(name: taskchainName))

        case .TaskChainCompleted:
            // TODO: (Achievement) Mirror WPF task-completion achievement progress.
            if info.taskchain == "Infrast" {
                finishInfrastRotation(coreID: info.taskid, succeeded: true)
            }
            if let id = taskID(coreID: info.taskid) {
                taskStatus[id] = .success
            }
            if info.taskchain == "Fight", let report = logStore?.sanityReport {
                logTrace(.completeTaskWithSanity(name: taskchainName, cur: report.current, max: report.maximum))
            } else {
                logTrace(.completeTask(name: taskchainName))
            }

        case .TaskChainExtraInfo:
            let what: String? = try? message.details["what"]
            let why: String? = try? message.details["why"]
            if what == "RoutingRestart", why == "TooManyBattlesAhead" {
                if let nodeCost: Int = try? message.details["node_cost"] {
                    logWarn(.routingRestartTooManyBattles(cost: nodeCost))
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

@JSONRepresentable
private struct MissingOperatorDetails {
    let name: String
}

@JSONRepresentable
private struct BattleFormationErrorDetails {
    let opers: [String: [MissingOperatorDetails]]
}

private func localizedWhy(_ why: String?) -> String {
    switch why {
    case "recognition error": L(.identifyTheMistakes)
    case "refresh count reached the limit": L(.recruitRefreshLimitReached)
    case "UnknownStage": L(.penguinUploadUnknownStage)
    case "NotThreeStars": L(.penguinUploadNotThreeStars)
    case "UnknownTimes": L(.penguinUploadUnknownTimes)
    case "UnknownDropType": L(.penguinUploadUnknownDropType)
    case "UnknownDrops": L(.penguinUploadUnknownDrops)
    case nil: L(.errorOccurred)
    case .some(let why): why
    }
}

extension MAAViewModel {
    private func processSubTaskError(_ details: JSON) {
        guard let info = SubTaskErrorMessage(json: details, context: "SubTaskError") else {
            return
        }

        switch info.subtask {
        case "StartGameTask":
            logError(.failedToOpenClient)

        case "StopGameTask":
            logError(.closeArknightsFailed)

        case "AutoRecruitTask":
            logError(.hasReturned(reason: localizedWhy(info.why)))

        case "RecognizeDrops":
            logError(.dropRecognitionError)

        case "ReportToPenguinStats":
            if case .fight(let config) = dailyTask(coreID: info.taskid), config.stage == "Annihilation" {
                logTrace(.giveUpUploadingPenguins(reason: L(.annihilationStage)))
            } else {
                logWarn(.giveUpUploadingPenguins(reason: localizedWhy(info.why)))
            }

        case "CheckStageValid":
            logError(.theEx)

        case "BattleFormationTask":
            // TODO: (Achievement) Record formations missing multiple operator groups.
            if info.why == "OperatorMissing", let payload = info.details,
                let formation = BattleFormationErrorDetails(json: payload, context: "BattleFormationError")
            {
                let groups = formation.opers.map { group, opers in
                    if opers.count == 1 {
                        return group
                    } else {
                        let names = opers.map(\.name).joined(separator: "/")
                        return "\(group) => \(names)"
                    }
                }.joined(separator: "\n")
                logError(.missingOperators(groups: groups))
            }

        case "CopilotTask":
            if info.what == "UserAdditionalOperInvalid", let payload = info.details,
                let name: String = try? payload["name"]
            {
                logError(.copilotUserAdditionalNameInvalid(name: name))
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
                // TODO: (LogCard) Start a new fight log card section.
                let sanityCost = logStore?.fightReport?.sanityCost.map { "\($0)" } ?? "???"
                let times: String
                if let report = logStore?.fightReport,
                    let timesFinished = report.timesFinished,
                    let series = report.series, series > 0
                {
                    let next = timesFinished + 1
                    times = series == 1 ? "\(next)" : "\(next)~\(timesFinished + series)"
                } else {
                    times = "???"
                }

                var statusParts = [LocalizedStringResource]()
                if let report = logStore?.sanityReport {
                    statusParts.append(.currentSanity(cur: report.current, max: report.maximum))
                }
                if expiringMedicineUsedTimes > 0 {
                    statusParts.append(.medicineUsedTimesWithExpiring(medicineUsedTimes, expiringMedicineUsedTimes))
                } else if medicineUsedTimes > 0 {
                    statusParts.append(.medicineUsedTimes(medicineUsedTimes))
                }
                if let stoneUsedTimes = logStore?.stoneUsedTimes, stoneUsedTimes > 0 {
                    statusParts.append(.stoneUsedTimes(stoneUsedTimes))
                }
                let statusString = statusParts.map(L).joined(separator: "  ")
                let statusSuffix = statusParts.isEmpty ? "" : "\n\(statusString)"
                logInfo(.missionStartFightTask(times: times, cost: sanityCost, using: statusSuffix))

            case "StoneConfirm":
                logInfo(.stoneUsed(times: process.exec_times))
                logStore?.stoneUsedTimes += 1

            case "AbandonAction":
                logError(.actingCommandError)

            case "FightMissionFailedAndStop":
                // TODO: (Notification) Show the fight-failure notification.
                logError(.fightMissionFailedAndStop)

            case "CheckEncounter-Uncollected":
                // TODO: (LogCard) Update the uncollected-reward log card.
                // TODO: (Notification) Show the uncollected-reward notification.
                // TODO: (ExternalNotification) Send the uncollected-reward event.
                logWarn("MiniGame@InteractiveExhibition@UncollectedNotificationContent")

            case "RecruitRefreshConfirm":
                logInfo(.labelsRefreshed)

            case "RecruitConfirm":
                // TODO: (LogCard) Update the recruit-confirmation log card.
                // TODO: (Achievement) Record recruit-confirmation progress.
                if let logStore {
                    logStore.recruitConfirmTimes += 1
                    logInfo(.recruitConfirm(times: logStore.recruitConfirmTimes))
                }

            case "InfrastDormDoubleConfirmButton":
                logInfo(.infrastDormDoubleConfirmed)

            case "ExitThenAbandon":
                // TODO: (Achievement) Record Roguelike retreats.
                logWarn(.explorationAbandoned)

            case "StartAction":
                // WPF retains this callback branch but currently performs no operation.
                break

            case "MissionCompletedFlag":
                // TODO: (LogCard) Update the Roguelike battle-success log card.
                logInfo(.fightCompleted)

            case "MissionFailedFlag":
                // TODO: (LogCard) Update the Roguelike battle-failure log card.
                logError(.fightFailed)

            case "StageTrader":
                logInfo(.trader)

            case "StageSafeHouse":
                logInfo(.safeHouse)

            case "StageFilterTruth":
                logInfo(.filterTruth)

            case "StageBoonsEnter":
                // WPF retains this callback branch but currently performs no operation.
                break

            case "StageCombatOps":
                logInfo(.combatOps)

            case "StageEmergencyOps":
                logWarn(.emergencyOps)

            case "StageDreadfulFoe", "StageDreadfulFoe-5":
                logError(.dreadfulFoe)

            case "StageTraderInvestSystemFull":
                logInfo(.upperLimit)

            case "OfflineConfirm", "OfflineConfirmAfterBattle":
                // TODO: (Notification) Show the game-disconnection notification.
                logError(.gameDrop)
                Task {
                    do {
                        try await stop()
                    } catch {
                        logger.warning("Failed to stop after game disconnect: \(error)")
                    }
                }

            case "GamePass":
                // TODO: (Achievement) Record completed Roguelike runs.
                logRare(.roguelikeGamePass)

            case "BattleStartAll":
                logInfo(.missionStart)

            case "StageDrops-Stars-3", "StageDrops-Stars-Adverse":
                // TODO: (ViewState) Mark the current Copilot task as successful.
                logInfo(.completeCombat)

            case "StageTraderSpecialShoppingAfterRefresh":
                logRare(.roguelikeSpecialItemBought)

            case "DeepExplorationNotUnlockedComplain":
                logWarn(.deepExplorationNotUnlockedComplain)

            case "PNS-Resume":
                logError(.reclamationPnsModeError)

            case "PIS-Commence":
                logError(.reclamationPisModeError)

            default:
                break
            }

        case "CombatRecordRecognitionTask":
            if let what = info.what {
                logTrace(verbatim: what)
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
                // TODO: (Achievement) Record clue-exchange progress.
                logTrace(.clueExchangeUnlocked)
            case "SendClues":
                // TODO: (Achievement) Record sent-clue progress as WPF does.
                break
            default:
                break
            }

        case "Roguelike":
            if process.task == "StartExplore" {
                logInfo(.begunToExplore(times: process.exec_times))
            }

        case "Mall":
            switch process.task {
            case "StageDrops-Stars-3":
                // TODO: (Achievement) Record completed credit fights.
                if let id = taskID(coreID: info.taskid),
                    case .mall(var config) = tasks[id]
                {
                    config.creditFightDate = .now
                    tasks[id] = .mall(config)
                }
                logInfo(.completeTask(name: L(.creditFight)))
            case "VisitLimited":
                if let id = taskID(coreID: info.taskid),
                    case .mall(var config) = tasks[id]
                {
                    config.friendVisitDate = .now
                    tasks[id] = .mall(config)
                }
                logInfo(.completeTask(name: L(.visiting)))
            case "VisitNextBlack":
                logInfo(.completeTask(name: L(.visiting)))
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
    let annihilation_weekly_process: [Int]?
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

@JSONRepresentable
private struct SanityBeforeStageDetails {
    let current_sanity: Int?
    let max_sanity: Int?
    let report_time: String?
}

@JSONRepresentable
private struct FightTimesDetails {
    let sanity_cost: Int?
    let series: Int?
    let times_finished: Int?
    let finished: Bool?
}

private let sanityReportTimeParser = Date.ParseStrategy(
    format:
        "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits).\(secondFraction: .fractional(3))",
    locale: Locale(identifier: "en_US_POSIX"),
    timeZone: .current)

extension MAAViewModel {
    private func processSubTaskExtraInfo(_ details: JSON) {
        guard let info = SubTaskExtraInfoMessage(json: details, context: "SubTaskExtraInfo") else {
            return
        }

        switch info.taskchain {
        case "Recruit":
            // TODO: (ViewState) Forward every Recruit callback to the recruit-calculation state.
            break

        case "Depot":
            // TODO: (Persistence) Persist Depot recognition results and synchronization metadata.
            logStore?.setDepot(.init(json: info.details, context: "Depot"))

        case "OperBox":
            // TODO: (Persistence) Persist OperBox recognition results and synchronization metadata.
            logStore?.setOperBox(.init(json: info.details, context: "OperBox"))

        default:
            break
        }

        switch info.what {
        case "StageDrops":
            // TODO: (Tooltip) Show recognized drop details.
            // TODO: (LogCard) Update the stage-drop log card.
            // TODO: (DataSync) Merge recognized drops into Depot data.
            // TODO: (Achievement) Record sanity-spending progress.
            guard let dropInfo = StageDropsDetails(json: info.details, context: "StageDrops") else {
                return
            }
            let drops = dropInfo.stats
                .sorted {
                    ($0.addQuantity, $0.quantity) > ($1.addQuantity, $1.quantity)
                }
                .map { item in
                    let itemName = item.itemName == "furni" ? L(.furnitureDrop) : item.itemName
                    return item.addQuantity > 0
                        ? "\(itemName) : \(item.quantity) (+\(item.addQuantity))"
                        : "\(itemName) : \(item.quantity)"
                }
            let dropText = drops.isEmpty ? L(.noDrop) : drops.joined(separator: "\n")
            let stageCode = dropInfo.stage?.stageCode ?? ""
            var extraInfo = [LocalizedStringResource]()
            if let curTimes = dropInfo.cur_times, curTimes > 0 {
                extraInfo.append(.curTimes(times: curTimes))
            }
            if let annihilation = dropInfo.annihilation_weekly_process, annihilation.count == 2 {
                extraInfo.append(.annihilationMode(cur: annihilation[0], max: annihilation[1]))
            }
            let extras = extraInfo.map(L).joined(separator: "\n")
            let extraLine = extraInfo.isEmpty ? "" : "\n\(extras)"
            logTrace(.totalDrop(code: stageCode, drops: dropText, extras: extraLine))

        case "EnterFacility":
            // TODO: (LogCard) Start a new infrastructure-room log card section.
            let facilityText: String
            if let facilityName: String = try? info.details["facility"] {
                if let facility = InfrastConfiguration.Facility(rawValue: facilityName) {
                    facilityText = facility.description
                } else {
                    facilityText = l(facilityName)
                }
            } else {
                facilityText = L("未知")
            }
            let indexText: String
            if let index: Int = try? info.details["index"] {
                indexText = String(format: "%02d", index + 1)
            } else {
                indexText = ""
            }
            logTrace(.thisFacility(facility: facilityText, index: indexText))

        case "ProductIncorrect":
            logError(.productIncorrect)

        case "ProductUnknown":
            logError(.productUnknown)

        case "ProductChanged":
            logInfo(.productChanged)

        case "ProductChangeFail":
            logError(.productChangeFail)

        case "InfrastConfirmButton":
            // TODO: (Screenshot) Fetch the latest infrastructure screenshot.
            // TODO: (LogCard) Update the infrastructure-confirmation log card.
            break

        case "RecruitTagsDetected":
            // TODO: (LogCard) Start a new recruit-result log card section.
            // TODO: (Screenshot) Update the recruit card with the current screenshot.
            let tags: [String] = (try? info.details["tags"]) ?? []
            let tagText = tags.isEmpty ? L(.error) : tags.joined(separator: "\n")
            logTrace(.recruitingResults(tags: tagText))

        case "RecruitSpecialTag", "RecruitRobotTag":
            // TODO: (Notification) Show the matching special-tag recruit notification.
            guard let _: String = try? info.details["tag"] else {
                return
            }

        case "RecruitPreservedTag":
            // TODO: (Notification) Show the matching preserved-tag recruit notification.
            guard let tag: String = try? info.details["tag"] else {
                return
            }
            logTrace(.recruitingTips(preserved: tag))

        case "RecruitResult":
            // TODO: (Tooltip) Show detailed recruit combinations.
            // TODO: (LogStyle) Emphasize high-rarity recruit results.
            // TODO: (Notification) Show high-rarity recruit notifications.
            // TODO: (Achievement) Mirror WPF recruit-result achievement progress.
            guard let level: Int = try? info.details["level"] else {
                return
            }
            if level >= 5 {
                logRare("\(level) ★ Tags")
            } else {
                logInfo("\(level) ★ Tags")
            }
            recruit = MAARecruit(json: info.details, context: "RecruitResult")

        case "RecruitSupportOperator":
            guard let name: String = try? info.details["name"] else {
                return
            }
            logInfo(.recruitSupportOperator(name: name))

        case "RecruitTagsSelected":
            let tags: [String] = (try? info.details["tags"]) ?? []
            let selected = tags.isEmpty ? L(.noDrop) : tags.joined(separator: "\n")
            logTrace(.recruitTagsSelectedLog(tags: selected))

        case "RecruitTagsRefreshed":
            // TODO: (Achievement) Record recruit-tag refreshes.
            guard let count: Int = try? info.details["count"] else {
                return
            }
            logTrace(.refreshed(times: count))

        case "RecruitNoPermit":
            guard let shouldContinue: Bool = try? info.details["continue"] else {
                return
            }
            if shouldContinue {
                logTrace(.continueRefresh)
            } else {
                logTrace(.noRecruitmentPermit)
            }

        case "NotEnoughStaff":
            logError(.notEnoughStaff)

        case "CreditFullOnlyBuyDiscount":
            guard let credit: Int = try? info.details["credit"] else {
                return
            }
            logTrace(.creditFullOnlyBuyDiscount(credit: credit))

        case "AccountSwitch":
            let accountName: String = (try? info.details["account_name"]) ?? ""
            logTrace(.accountSwitch(to: accountName))

        case "StageInfo":
            // TODO: (ViewState) Mark delayed Roguelike aborts as waiting for combat to finish.
            guard let name: String = try? info.details["name"] else {
                return
            }
            logTrace(.startCombat(name: name))

        case "StageInfoError":
            // TODO: (LogCard) Split the stage-error log card.
            // TODO: (Screenshot) Update the stage-error card with the current screenshot.
            logError(.stageInfoError)

        case "BattleFormation":
            // TODO: (Localization) Localize operator names.
            let formation: [String] = (try? info.details["formation"]) ?? []
            logTrace(.battleFormation(formation.joined(separator: ", ")))

        case "BattleFormationParseFailed":
            logTrace(.battleFormationParseFailed)

        case "BattleFormationSelected":
            // TODO: (Localization) Localize the selected operator name.
            let selected: String = (try? info.details["selected"]) ?? ""
            let groupName: String? = try? info.details["group_name"]
            let displayName: String
            if let groupName, groupName != selected {
                displayName = "\(groupName) => \(selected)"
            } else {
                displayName = selected
            }
            logTrace(.battleFormationSelected(groupOrName: displayName))

        case "BattleFormationOperUnavailable":
            // TODO: (ViewState) Record that Copilot requirements were ignored.
            // TODO: (Localization) Localize the operator name.
            // TODO: (Localization) Localize the unavailable requirement type.
            // TODO: (LogStyle) Use warning or error styling according to requirement settings.
            let operName: String = (try? info.details["oper_name"]) ?? ""
            let typeName: String
            let type: String? = try? info.details["requirement_type"]
            switch type {
            case "elite": typeName = L(.battleFormationOperUnavailableElite)
            case "level": typeName = L(.battleFormationOperUnavailableLevel)
            case "skill_level": typeName = L(.battleFormationOperUnavailableSkillLevel)
            case "module": typeName = L(.battleFormationOperUnavailableModule)
            default: typeName = "Unknown Type"
            }
            logError(.battleFormationOperUnavailable(name: operName, reason: typeName))

        case "CopilotAction":
            // TODO: (LogStyle) Apply the callback-provided document color.
            // TODO: (Localization) Localize Copilot action names.
            // TODO: (Localization) Localize target operator names.
            guard let action = CopilotActionDetails(json: info.details, context: info.what) else {
                return
            }
            if let doc = action.doc, !doc.isEmpty {
                logTrace(verbatim: doc)
            }
            logTrace(.currentSteps(action: action.action, target: action.target ?? ""))
            if let elapsedTime = action.elapsed_time, elapsedTime >= 0 {
                logTrace(.elapsedTime(time: elapsedTime))
            }

        case "CopilotListLoadTaskFileSuccess":
            // TODO: (ViewState) Store the current Copilot ID.
            // TODO: (ViewState) Reset the ignored-requirement state.
            guard let file = CopilotFileDetails(json: info.details, context: info.what) else {
                return
            }
            logTrace("解析 \(file.file_name)[\(file.stage_name)] 成功")

        case "SSSStage":
            guard let stage: String = try? info.details["stage"] else {
                return
            }
            logInfo(.currentStage(stage: stage))

        case "SSSSettlement":
            if let why = info.why {
                logInfo(verbatim: why)
            }

        case "SSSGamePass":
            logRare(.sssgamePass)

        case "UnsupportedLevel":
            // TODO: (ResourceUpdate) Update resources and reload them into Core.
            let level = (try? info.details["level"]) ?? .null
            logError(.unsupportedLevel(level: level.description))

        case "CustomInfrastRoomGroupsMatch":
            guard let group: String = try? info.details["group"] else {
                return
            }
            logTrace(.roomGroupsMatch(group: group))

        case "CustomInfrastRoomGroupsMatchFailed":
            guard let groups: [String] = try? info.details["groups"] else {
                return
            }
            logTrace(.roomGroupsMatchFailed(groups: groups.joined(separator: ", ")))

        case "CustomInfrastRoomOperators":
            // TODO: (Localization) Localize infrastructure operator names.
            let names: [String] = (try? info.details["names"]) ?? []
            logTrace(.roomOperators(names: names.joined(separator: ", ")))

        case "InfrastTrainingIdle":
            logTrace(.trainingIdle)

        case "InfrastTrainingCompleted", "InfrastTrainingTimeLeft":
            // TODO: (Localization) Localize the training operator name.
            let oper: String = (try? info.details["operator"]) ?? "UnKnown"
            let skill: String = (try? info.details["skill"]) ?? "UnKnown"
            let level: Int = (try? info.details["level"]) ?? -1
            if info.what == "InfrastTrainingCompleted" {
                logInfo(.trainingCompleted(oper: oper, skill: skill, level: level))
            } else {
                let time: String = (try? info.details["time"]) ?? "Unknown"
                logInfo(.trainingTimeLeft(oper: oper, skill: skill, level: level, time: time))
            }

        case "ReclamationReport":
            let totalBadges: Int = (try? info.details["total_badges"]) ?? -1
            let badges: Int = (try? info.details["badges"]) ?? -1
            let totalPoints: Int = (try? info.details["total_construction_points"]) ?? -1
            let points: Int = (try? info.details["construction_points"]) ?? -1
            logTrace(.algorithmFinish(badges: "\(totalBadges)(+\(badges))", points: "\(totalPoints)(+\(points))"))

        case "ReclamationProcedureStart":
            guard let times: Int = try? info.details["times"] else {
                return
            }
            logInfo(.missionStartTimes(times))

        case "ReclamationSmeltGold":
            guard let times: Int = try? info.details["times"] else {
                return
            }
            logTrace(.algorithmDoneSmeltGold(times: times))

        case "RoguelikeInvestmentReachFull":
            logInfo(.roguelikeInvestmentReachFull)

        case "RoguelikeInvestmentReachLimit":
            guard let limit: Int = try? info.details["limit"] else {
                return
            }
            logInfo(.roguelikeInvestmentReachLimit(limit: limit))

        case "RoguelikeInvestment":
            guard let investment = RoguelikeInvestmentDetails(json: info.details, context: info.what) else {
                return
            }
            logInfo(.roguelikeInvestment(count: investment.count, total: investment.total, deposit: investment.deposit))

        case "RoguelikeSettlement":
            // TODO: (DataCorrection) Validate and correct difficulty OCR for the selected theme.
            // TODO: (LogCard) Update the Roguelike settlement log card.
            // TODO: (Screenshot) Update the settlement card with the current screenshot.
            guard let settlement = RoguelikeSettlementDetails(json: info.details, context: info.what) else {
                return
            }
            logTrace(
                .roguelikeSettlement(
                    pass: settlement.game_pass ? "✓" : "✗",
                    floor: settlement.floor ?? 0, step: settlement.step ?? 0,
                    combat: settlement.combat ?? 0, emergency: settlement.emergency ?? 0, boss: settlement.boss ?? 0,
                    recruit: settlement.recruit ?? 0, collection: settlement.collection ?? 0,
                    difficulty: settlement.difficulty ?? 0, score: settlement.score ?? 0,
                    exp: settlement.exp ?? "", skill: settlement.skill ?? "")
            )

        case "RoguelikeCombatEnd":
            // TODO: (ViewState) Clear the delayed-abort and in-combat state.
            break

        case "RoguelikeEvent":
            guard let name: String = try? info.details["name"] else {
                return
            }
            logInfo(.roguelikeEvent(name: name))

        case "RoguelikeEncounterOptions":
            // TODO: (LogCard) Update the Roguelike encounter-options log card.
            // TODO: (Screenshot) Update the encounter-options card with the current screenshot.
            let options: [RoguelikeEncounterOptionDetails] = (try? info.details["options"]) ?? []
            let optionLines = options.map { option in
                if option.enabled {
                    L(.roguelikeEncounterEnabledOption(name: option.text))
                } else {
                    L(.roguelikeEncounterDisabledOption(name: option.text))
                }
            }.joined(separator: "\n")
            if optionLines.isEmpty {
                logInfo("没有识别到选项")
            } else {
                logInfo(.roguelikeEncounterOptions(count: options.count, options: optionLines))
            }

        case "BlackFlowRoutingDecision":
            // TODO: (Localization) Localize BlackFlow movement values.
            // TODO: (Localization) Localize BlackFlow node types.
            // TODO: (Localization) Localize BlackFlow reason categories.
            // TODO: (Localization) Localize BlackFlow reason details.
            guard let decision = BlackFlowRoutingDecisionDetails(json: info.details, context: info.what) else {
                return
            }
            let node = decision.node_name.map { $0.isEmpty ? decision.node_type : $0 } ?? decision.node_type
            logInfo(
                .blackFlowRoutingDecision(
                    floor: decision.floor, before: decision.action_points_before, after: decision.action_points_after,
                    movement: decision.movement, node: node,
                    margin: decision.safety_margin)
            )
            logInfo(.blackFlowRoutingReason(reason: decision.reason_category, detail: decision.reason_detail ?? ""))

        case "BlackFlowRoutingWarning":
            let code: String = (try? info.details["code"]) ?? ""
            switch code {
            case "map_rebuild_failed": logWarn(.blackFlowWarningMapRebuildFailed)
            case "page_recovery_failed": logWarn(.blackFlowWarningPageRecoveryFailed)
            case "preview_cost_changed": logWarn(.blackFlowWarningPreviewCostChanged)
            case "route_blocked": logWarn(.blackFlowWarningRouteBlocked)
            case "insufficient_action_points": logWarn(.blackFlowWarningInsufficientActionPoints)
            case "target_state_changed": logWarn(.blackFlowWarningTargetStateChanged)
            case "target_unreachable": logWarn(.blackFlowWarningTargetUnreachable)
            case "inferred_edge_selected": logWarn(.blackFlowWarningInferredEdge)
            case "post_move_mismatch": logWarn(.blackFlowWarningPostMoveMismatch)
            case "identity_conflict": logWarn(.blackFlowWarningIdentityConflict)
            default: logWarn(.blackFlowWarningUnknown)
            }

        case "BlackFlowMilestoneChanged":
            // TODO: (Localization) Localize BlackFlow milestone identifiers.
            // TODO: (Localization) Localize BlackFlow milestone status values.
            let status: String = (try? info.details["status"]) ?? ""
            let milestoneId: String = (try? info.details["milestone_id"]) ?? ""
            if status != "inactive" {
                logInfo(.blackFlowMilestoneChanged(id: milestoneId, status: status))
            }

        case "BlackFlowStrategyStarted":
            // TODO: (Localization) Localize the BlackFlow profile value.
            let profile: String = (try? info.details["profile"]) ?? ""
            logInfo(.blackFlowStrategyStarted(profile: profile))

        case "BlackFlowStrategyResult":
            // TODO: (Localization) Localize the BlackFlow outcome value.
            // TODO: (Localization) Localize the BlackFlow termination reason.
            let outcome: String = (try? info.details["outcome"]) ?? ""
            let reason: String = (try? info.details["termination_reason"]) ?? ""
            let success: Bool = (try? info.details["succeeded"]) ?? false
            if success {
                logInfo(.blackFlowStrategyResult(outcome: outcome, reason: reason))
            } else {
                logWarn(.blackFlowStrategyResult(outcome: outcome, reason: reason))
            }

        case "BoskyPassageNode":
            guard let nodeType: String = try? info.details["node_type"] else {
                return
            }
            switch nodeType {
            case "Omissions": logInfo(.boskyOmissions)
            case "Legend": logInfo(.boskyLegend)
            case "OldShop": logInfo(.boskyOldShop)
            case "YiTrader": logInfo(.boskyYiTrader)
            case "Scheme": logInfo(.boskyScheme)
            case "Playtime": logInfo(.boskyPlaytime)
            case "Doubts": logInfo(.boskyDoubts)
            case "Disaster": logWarn(.boskyDisaster)
            default: logInfo(verbatim: nodeType)
            }

        case "RoguelikeCoppersRecognitionError":
            let recognizedName: String = (try? info.details["recognized_name"]) ?? "Unknown"
            logError(.roguelikeCoppersRecognitionError(name: recognizedName))

        case "RoguelikeCoppersExchangeInfo":
            let toDiscard: String = (try? info.details["to_discard"]) ?? "Unknown"
            let toPickup: String = (try? info.details["to_pickup"]) ?? "Unknown"
            logInfo(.roguelikeCoppersExchange(from: toDiscard, to: toPickup))

        case "EncounterOcrError":
            logError(.encounterOcrError)

        case "RoguelikeJieGardenTargetFound":
            let targetSubtype: String = (try? info.details["target_subtype"]) ?? "Unknown"
            let targetName: String
            switch targetSubtype {
            case "Ling": targetName = L(.roguelikePlaytimeLing)
            case "Shu": targetName = L(.roguelikePlaytimeShu)
            case "Nian": targetName = L(.roguelikePlaytimeNian)
            default: targetName = targetSubtype
            }
            logInfo(.roguelikeJieGardenTargetFound(name: targetName))

        case "FoldartalGainOcrNextLevel":
            let foldartal: String = (try? info.details["foldartal"]) ?? ""
            logTrace(.foldartalGainOcrNextLevel(name: foldartal))

        case "MonthlySquadCompleted":
            logRare(.monthlySquadCompleted)

        case "DeepExplorationCompleted":
            logRare(.deepExplorationCompleted)

        case "RoguelikeCollapsalParadigms":
            guard let deepenOrWeaken: Int = try? info.details["deepen_or_weaken"] else {
                return
            }
            let current: String = (try? info.details["cur"]) ?? "UnKnown"
            let previous: String = (try? info.details["prev"]) ?? "UnKnown"
            if deepenOrWeaken == 1, previous.isEmpty {
                logInfo(.roguelikeGainParadigm(current))
            } else if deepenOrWeaken == 1 {
                logInfo(.roguelikeDeepenParadigm(from: previous, to: current))
            } else if deepenOrWeaken == -1, current.isEmpty {
                logInfo(.roguelikeLoseParadigm(previous))
            } else if deepenOrWeaken == -1 {
                logInfo(.roguelikeWeakenParadigm(from: previous, to: current))
            }

        case "UseMedicine":
            // TODO: (Achievement) Mirror WPF medicine-usage achievement progress.
            guard let medicine = UseMedicineDetails(json: info.details, context: info.what) else {
                return
            }
            let expiry: String
            if case .fight(let config) = dailyTask(coreID: info.taskid),
                config.medicine_expire_days > 0
            {
                expiry = L(config.localizedExpiry)
            } else {
                expiry = L("即将")
            }
            if medicine.is_expiring {
                expiringMedicineUsedTimes += medicine.count
                logInfo(.expiringMedicineUsed(expiry: expiry, total: expiringMedicineUsedTimes, count: medicine.count))
            } else {
                medicineUsedTimes += medicine.count
                logInfo(.medicineUsed(total: medicineUsedTimes, count: medicine.count))
            }
            for item in medicine.medicines ?? [] {
                logInfo(.useMedicineMedicineInfo(use: item.use, inventory: item.inventory))
            }

        case "SanityBeforeStage":
            logStore?.sanityReport = nil
            guard let details = SanityBeforeStageDetails(json: info.details, context: info.what),
                let current = details.current_sanity,
                let maximum = details.max_sanity,
                maximum > 0
            else {
                return
            }
            let reportedAt: Date?
            if let reportTime = details.report_time {
                do {
                    reportedAt = try sanityReportTimeParser.parse(reportTime)
                } catch {
                    logger.error("Failed to parse SanityBeforeStage report_time: \(error); value: \(reportTime)")
                    reportedAt = nil
                }
            } else {
                reportedAt = nil
            }
            logStore?.sanityReport = NewViewModel.SanityReport(
                current: current, maximum: maximum, reportedAt: reportedAt)

        case "FightTimes":
            // TODO: (Achievement) Record completed fight-count progress.
            logStore?.fightReport = nil
            guard let details = FightTimesDetails(json: info.details, context: info.what) else {
                return
            }
            logStore?.fightReport = NewViewModel.FightReport(
                sanityCost: details.sanity_cost,
                series: details.series,
                timesFinished: details.times_finished,
                finished: details.finished)
            if case .fight(let config) = dailyTask(coreID: info.taskid),
                let limit = config.times, let series = details.series,
                let timesFinished = details.times_finished,
                timesFinished < limit, details.finished == true
            {
                let nextFinished = timesFinished + series
                logWarn(.fightTimesUnused(times: timesFinished, series: series, upTo: nextFinished, limit: limit))
            }

        case "StageQueueUnableToAgent":
            guard let stageCode: String = try? info.details["stage_code"] else {
                return
            }
            logInfo(.unableToAgent(stage: stageCode))

        case "StageQueueMissionCompleted":
            guard let stageCode: String = try? info.details["stage_code"],
                let stars: Int = try? info.details["stars"]
            else {
                return
            }
            logInfo(.stageQueue(stage: stageCode, stars: stars))

        case let what where what.starts(with: "MaterialSynthesis"):
            // There is no plan to re-run Material Synthesis currently.
            break

        case "PixelPaintProgress":
            // TODO: (LogStyle) Apply the current palette color to progress logs.
            let done: Int = (try? info.details["done"]) ?? 0
            let total: Int = (try? info.details["total"]) ?? 0
            if done >= total, total > 0 {
                logInfo(.miniGamePixelPaintDoneLog)
            } else {
                logTrace(.miniGamePixelPaintProgressLog(done: done, total: total))
            }

        case "Finished" where info.taskchain == "VideoRecognition":
            guard let filename: String = try? info.details["filename"] else {
                return
            }
            do {
                let url = URL(filePath: filename)
                let dst = try FileManager.default.moveCopilotToExternalDirectory(at: url)
                logStore?.setLastImportedCopilot(dst)
                logInfo("已添加：\(dst.deletingPathExtension().lastPathComponent)")
            } catch {
                logError("无法添加视频作业：\(error.localizedDescription)")
            }

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
        logTrace(verbatim: .init(localized: resource))
    }

    func logInfo(_ resource: LocalizedStringResource) {
        logInfo(verbatim: .init(localized: resource))
    }

    func logWarn(_ resource: LocalizedStringResource) {
        logWarn(verbatim: .init(localized: resource))
    }

    func logRare(_ resource: LocalizedStringResource) {
        logRare(verbatim: .init(localized: resource))
    }

    func logError(_ resource: LocalizedStringResource) {
        logError(verbatim: .init(localized: resource))
    }

    func logTrace(verbatim content: String) {
        writeLog(color: .trace, content)
    }

    func logInfo(verbatim content: String) {
        writeLog(color: .info, content)
    }

    func logWarn(verbatim content: String) {
        writeLog(color: .warning, content)
    }

    func logRare(verbatim content: String) {
        writeLog(color: .rare, content)
    }

    func logError(verbatim content: String) {
        writeLog(color: .error, content)
    }

    private func writeLog(color: MAALog.LogColor, _ content: String) {
        let entry = MAALog(date: Date(), content: content, color: color)
        logStore?.appendLog(entry)
    }

    func dailyTask(coreID: Int32?) -> MAATask? {
        guard let id = taskID(coreID: coreID) else { return nil }
        return tasks[id]
    }

    private func taskID(coreID: Int32?) -> UUID? {
        if let coreID,
            let id = taskIDMap[coreID]
        {
            return id
        } else {
            return nil
        }
    }
}
