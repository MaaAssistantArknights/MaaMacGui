//
//  MAAViewModel.swift
//  MAA
//
//  Created by hguandl on 13/4/2023.
//

import Combine
import IOKit.pwr_mgt
import SwiftUI

@MainActor class MAAViewModel: ObservableObject {
    // MARK: - Core Status

    enum Status: Equatable {
        case busy
        case idle
        case pending
    }

    var medicineUsedTimes = 0
    var expiringMedicineUsedTimes = 0

    @Published private(set) var status = Status.idle
    @Published private(set) var isCoreInitialized = false

    private var wakeupAssertionID: UInt32?
    private var awakeAssertionID: UInt32?
    private var handle: MAAHandle?
    private var cancellables = Set<AnyCancellable>()

    // 核心回调可能在异步操作返回前重置 status，独立标记防止入口重叠。
    @Published private(set) var isStartStopInFlight = false
    var forceRecovery: ForcedGameRecovery?
    var forceRecoveryInFlight = false
    private var forceRecoveryCleanupPending = false
    private var forceRecoveryJournalFailureRunID: UUID? = nil
    private var taskCompletionGeneration = UInt64(0)
    private var dailyCompletionTask: Task<Void, Never>?
    private var dailyFinishAttemptedRunID: UUID?

    let dailyRunCoordinator = DailyRunCoordinator(journalURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("DailyRunJournal.json"))
    private var dailyRunOutcome = DailyRunOutcome.completed
    private(set) var dailyRunTasks: [DailyTask]?
    private(set) var isApplyingDailyCallbackPatch = false

    var canStartTasks: Bool {
        status == .idle && !isStartStopInFlight && dailyRunCoordinator.active == nil
    }

    private func reconcileDailyRunStatus() {
        if status == .idle, let phase = dailyRunCoordinator.active?.status {
            status = phase == .running ? .busy : .pending
        }
    }

    private func beginTaskOperation(requiresIdle: Bool = true) async throws {
        reconcileDailyRunStatus()
        guard !isStartStopInFlight else {
            logError("当前正在启动或停止任务，请稍后重试。")
            throw MAAError.taskOperationInProgress
        }
        guard !requiresIdle || (status == .idle && dailyRunCoordinator.active == nil) else {
            logError("任务正在运行，请先停止当前任务。")
            throw MAAError.taskAlreadyRunning
        }
        // Reserve before querying the core actor: the await must not admit
        // another start or stop even if a callback has exposed idle.
        isStartStopInFlight = true
        var accepted = false
        defer {
            if !accepted { isStartStopInFlight = false }
        }

        if requiresIdle {
            let coreIsRunning = await handle?.running == true
            guard !coreIsRunning, status == .idle else {
                if coreIsRunning { status = .busy }
                logError("任务正在运行，请先停止当前任务。")
                throw MAAError.taskAlreadyRunning
            }
            try Task.checkCancellation()
        }
        accepted = true
    }

    // MARK: - Core Callback

    private var messageTask: Task<Void, Never>?
    weak var logStore: (any LogStore)?

    // MARK: - Daily Tasks

    @AppStorage("DailyTaskProfile") var dailyTaskProfile = "Default"

    enum DailyTasksDetailMode: Hashable {
        case taskConfig
        case log
        case timerConfig
    }

    @Published var tasks = [DailyTask]()
    @Published var taskIDMap: [Int32: UUID] = [:]
    @Published var newTaskAdded = false

    enum TaskStatus: Equatable {
        case cancel
        case failure
        case running
        case success
    }

    @Published var taskStatus: [UUID: TaskStatus] = [:]

    var tasksDirectory: URL {
        Self.userDirectory.appendingPathComponent("DailyTasks", isDirectory: true)
    }

    var tasksURL: URL {
        tasksDirectory.appendingPathComponent(dailyTaskProfile, isDirectory: false)
            .appendingPathExtension("plist")
    }

    @AppStorage("MAAScheduledDailyTaskTimer") var serializedScheduledDailyTaskTimers: String?

    typealias DailyTaskTimer = DailyTaskSchedule

    @Published var scheduledDailyTaskTimers: [DailyTaskTimer] = []

    // MARK: - OTA Resources

    @Published private var stageActivities = [String: MAAStageActivity]()

    var stageActivity: MAAStageActivity? {
        stageActivities[clientChannel.rawValue]
    }

    // MARK: - Recognition

    @Published var recruitConfig = RecruitConfiguration.recognition
    @Published var recruit: MAARecruit?

    // MARK: - Connection Settings

    @AppStorage("MAAConnectionAddress") var connectionAddress = "127.0.0.1:5555"

    @AppStorage("MAAUseGzip") var useGzip = false

    @AppStorage("MAAUseAdbLite") var useAdbLite = true

    @AppStorage("MAAToolsMode") var toolsMode = MaaToolsMode.BGR

    @AppStorage("MAATouchMode") var touchMode = MaaTouchMode.maatouch {
        didSet {
            guard touchMode != oldValue else { return }
            if touchMode == .MacPlayTools || oldValue == .MacPlayTools {
                Task { try await loadResource(channel: clientChannel) }
            }
        }
    }

    // MARK: - Game Settings

    @AppStorage("MAAClientChannel") var clientChannel = MAAClientChannel.Official {
        didSet {
            updateChannel(channel: clientChannel)
        }
    }

    // MARK: - Update Settings

    @AppStorage("AutoResourceUpdate") var autoResourceUpdate = false

    @AppStorage("ResourceUpdateChannel") var resourceChannel = MAAResourceChannel.github

    @Published var showResourceUpdate = false

    // MARK: - System Settings

    @AppStorage("MAAPreventSystemSleeping") var preventSystemSleeping = false {
        didSet {
            NotificationCenter.default.post(name: .MAAPreventSystemSleepingChanged, object: preventSystemSleeping)
        }
    }

    @AppStorage("MAAUseWebGPU") var useWebGPU = false

    // MARK: - Initializer

    init() {
        do {
            let data = try Data(contentsOf: tasksURL)
            tasks = try PropertyListDecoder().decode([DailyTask].self, from: data)
        } catch {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: tasksDirectory.path, isDirectory: &isDirectory)
            switch (exists, isDirectory.boolValue) {
            case (true, true):
                break
            case (true, false):
                try? FileManager.default.removeItem(at: tasksDirectory)
                try? FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
            case (false, _):
                try? FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
            }

            do {
                tasks = try migrateLegacyConfigurations()
            } catch {
                tasks = defaultTaskConfigurations.map { .init(config: $0) }
            }
        }

        $tasks.sink(receiveValue: writeBack).store(in: &cancellables)
        $status.sink(receiveValue: switchAwakeGuard).store(in: &cancellables)

        dailyRunCoordinator.didChange = { [weak self] in self?.objectWillChange.send() }
        initScheduledDailyTaskTimer()
    }

    deinit {
        messageTask?.cancel()
        Self.releaseAssertion(awakeAssertionID)
        Self.releaseAssertion(wakeupAssertionID)
    }
}

// MARK: - MaaCore

extension MAAViewModel {
    func initialize() async throws {
        status = .pending
        try await MAAProvider.shared.setUserDirectory(path: Self.userDirectory.path)
        if useWebGPU {
            try await MAAProvider.shared.setStaticOption(key: 2, value: "webgpu:0")
        }
        try await loadResource(channel: clientChannel)
        status = .idle
        isCoreInitialized = true
    }

    func ensureHandle(requireConnect: Bool = true) async throws {
        if handle == nil {
            let handle = try await MAAHandle(options: instanceOptions)
            self.handle = handle
            messageTask?.cancel()

            let messages = handle.messages
            messageTask = Task { [weak self, messages] in
                for await message in messages {
                    self?.processMessage(message)
                }
            }
        } else {
            // 实例已存在时重新应用选项（如触控模式），使设置变更在下次连接即生效，无需重启应用。
            try await handle?.apply(options: instanceOptions)
        }

        guard await handle?.running == false else {
            status = .busy
            logError("任务正在运行，请先停止当前任务。")
            throw MAAError.taskAlreadyRunning
        }

        logStore?.clearLogs()
        taskIDMap.removeAll()
        taskStatus.removeAll()

        guard requireConnect else { return }

        logTrace("ConnectingToEmulator")
        if touchMode == .MacPlayTools {
            logTrace("如果长时间连接不上或出错，请尝试下载使用“文件” > “PlayCover链接…”中的最新版本")
            if toolsMode == .MacSCK && !CGPreflightScreenCaptureAccess() {
                logError("未开启屏幕录制权限，请前往“系统设置” > “隐私与安全性” > “录屏与系统录音”允许MAA访问")
            }
            if toolsMode == .MacSCK {
                logInfo("运行过程中，请勿将游戏设置为全屏幕、最小化，或移动窗口至其他显示器")
            }
        }

        let connectionProfile: String
        switch (touchMode, toolsMode, useGzip) {
        case (.MacPlayTools, .MacSCK, _):
            connectionProfile = "MacSCK"
        case (.MacPlayTools, .BGR, _):
            connectionProfile = "MacBGR"
        case (_, _, true):
            connectionProfile = "Compatible"
        default:
            connectionProfile = "CompatMac"
        }

        try await handle?.connect(adbPath: adbPath, address: connectionAddress, profile: connectionProfile)
        logTrace("Running")
    }

    private func startCoreTasks(recordDailyTaskStart: Bool = false) async throws {
        try await handle?.start()
        // Reconcile the actual core after start. A reset may belong to a prior
        // run; retry if a callback makes the awaited running snapshot stale.
        var observedGeneration: UInt64
        var coreIsRunning: Bool
        repeat {
            observedGeneration = taskCompletionGeneration
            coreIsRunning = await handle?.running == true
        } while observedGeneration != taskCompletionGeneration

        guard coreIsRunning else {
            resetStatus()
            return
        }
        if recordDailyTaskStart { logStore?.taskStartTime = .now }
        status = .busy
    }

    func stop(cancelScheduledStart: Bool = true) async throws {
        if cancelScheduledStart {
            NotificationCenter.default.post(name: Notification.Name("MAACancelPendingScheduledStart"), object: nil)
        }
        guard dailyRunCoordinator.active?.status != .postHook else {
            logError("后置清理正在执行，请等待完成。")
            throw MAAError.taskOperationInProgress
        }
        try await beginTaskOperation(requiresIdle: false)
        defer { isStartStopInFlight = false }

        status = .pending
        defer { handleEarlyReturn(backTo: .busy) }

        dailyRunOutcome = .cancelled
        if let id = dailyRunCoordinator.active?.id {
            try dailyRunCoordinator.transition(.stopping, for: id)
        }
        try await handle?.stop()
        status = .idle
        await finishDailyRunIfStopped(allowInFlight: true)
    }

    func resetStatus() {
        taskCompletionGeneration &+= 1
        if let runID = dailyRunCoordinator.active?.id, dailyFinishAttemptedRunID == runID {
            status = .pending
            return
        }
        status = .idle
        medicineUsedTimes = 0
        expiringMedicineUsedTimes = 0

        logStore?.screencapCost = nil
        logStore?.lastScreencapWarningLevel = 0
        logStore?.hasPrintedFPSHighTip = false
        logStore?.taskStartTime = nil
        logStore?.sanityReport = nil
        logStore?.fightReport = nil
        logStore?.stoneUsedTimes = 0
        logStore?.recruitConfirmTimes = 0
        // Core emits AllTasksCompleted before its worker clears the running flag.
        // Keep checking for this run until the native shutdown and any start/stop
        // operation have finished; never let an old waiter finish a later run.
        guard let runID = dailyRunCoordinator.active?.id else { return }
        waitForDailyRunCompletion(runID: runID)
    }

    private func waitForDailyRunCompletion(runID: UUID) {
        dailyCompletionTask?.cancel()
        dailyCompletionTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.dailyRunCoordinator.active?.id == runID else { return }
                if await self.finishDailyRunIfStopped() { return }
                guard self.dailyRunCoordinator.active?.id == runID,
                      self.dailyRunCoordinator.active?.status != .postHook else { return }
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            }
        }
    }

    func markDailyRunFailed() {
        if dailyRunCoordinator.active != nil { dailyRunOutcome = .failed }
    }

    private func discardPreparedDailyTasks(for runID: UUID) async -> Bool {
        guard dailyRunCoordinator.active?.id == runID else { return false }
        do {
            try await handle?.stop()
            guard dailyRunCoordinator.active?.id == runID else { return false }
            guard await handle?.running != true else { throw MAAError.taskAlreadyRunning }
            taskIDMap.removeAll()
            taskStatus.removeAll()
            return true
        } catch {
            guard dailyRunCoordinator.active?.id == runID else { return false }
            messageTask?.cancel()
            messageTask = nil
            handle = nil
            taskIDMap.removeAll()
            taskStatus.removeAll()
            logError(verbatim: "Daily preparation cleanup: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    private func finishDailyRunIfStopped(allowInFlight: Bool = false) async -> Bool {
        guard allowInFlight || !isStartStopInFlight else { return false }
        guard let context = dailyRunCoordinator.active,
              [.running, .stopping].contains(context.status) || forceRecoveryCleanupPending else { return false }
        guard await handle?.running != true,
              (allowInFlight || !Task.isCancelled),
              (allowInFlight || !isStartStopInFlight),
              dailyRunCoordinator.active?.id == context.id,
              let currentStatus = dailyRunCoordinator.active?.status,
              [.running, .stopping].contains(currentStatus) || forceRecoveryCleanupPending else { return false }
        // A failed recovery retains Core and suppresses its callbacks until it is
        // observably idle. Only then may its queued work and handle be discarded.
        if forceRecoveryCleanupPending {
            messageTask?.cancel()
            messageTask = nil
            handle = nil
            forceRecovery = nil
            forceRecoveryCleanupPending = false
            forceRecoveryInFlight = false
            if forceRecoveryJournalFailureRunID == context.id {
                status = .pending
                return true
            }
        }
        // Failed journal writes keep ownership and must not spin on duplicate callbacks.
        guard dailyFinishAttemptedRunID != context.id else { return true }
        dailyFinishAttemptedRunID = context.id
        do {
            try dailyRunCoordinator.finish(context.id, outcome: dailyRunOutcome, cleanupSucceeded: true)
            dailyRunTasks = nil
            status = .idle
        } catch {
            status = .pending
            logError(verbatim: "Daily run journal: \(error.localizedDescription)")
        }
        return true
    }

    func screenshot() async throws -> NSImage {
        guard let image = try await handle?.getImage() else {
            throw MAAError.imageUnavailable
        }

        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    /// Reloads the resources from the documents directory after update.
    func reloadResources(channel: MAAClientChannel) async throws {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        try await loadResource(url: documentsDirectory, channel: channel)
    }

    /// Load base resources and channel-specific resources.
    ///
    /// Should be called by `loadResource(channel:)`.
    private func loadResource(url: URL, channel: MAAClientChannel) async throws {
        try await loadResource(url: url)

        if channel.isGlobal {
            let extraResource = url.appendingPathComponent("resource")
                .appendingPathComponent("global")
                .appendingPathComponent(channel.rawValue)
            if FileManager.default.fileExists(atPath: extraResource.path) {
                try await loadResource(url: extraResource)
            }
        }
    }

    /// Core process to load resources at url.
    ///
    /// Should be called by `loadResource(url:channel:)`.
    private func loadResource(url: URL) async throws {
        try await MAAProvider.shared.loadResource(path: url.path)

        if touchMode == .MacPlayTools {
            let platformResource = url.appendingPathComponent("resource")
                .appendingPathComponent("platform_diff")
                .appendingPathComponent("iOS")
            if FileManager.default.fileExists(atPath: platformResource.path) {
                try await MAAProvider.shared.loadResource(path: platformResource.path)
            }
        }
    }

    /// Fetches OTA resources for the specified channel.
    private func fetchOTAResource(channel: MAAClientChannel) async throws {
        let otaFetcher = OTAFetcher()
        var files = [
            (path: "resource/tasks.json", name: "resource/tasks/tasks.json"),
            (path: "gui/StageActivityV2.json", name: "gui/StageActivityV2.json"),
        ]
        if channel.isGlobal {
            files.append(
                (
                    path: "resource/global/\(channel.rawValue)/resource/tasks.json",
                    name: "resource/global/\(channel.rawValue)/resource/tasks/tasks.json"
                ))
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (path, name) in files {
                group.addTask {
                    try await otaFetcher.download(path: path, name: name)
                }
            }
            try await group.waitForAll()
        }
        let data = try otaFetcher.data(name: "gui/StageActivityV2.json")
        let decoder = JSONDecoder()
        stageActivities = try decoder.decode([String: MAAStageActivity].self, from: data)
    }

    /// Load resources from bundled, user, and remote resources.
    ///
    /// Should be the outermost call to load resources.
    private func loadResource(channel: MAAClientChannel) async throws {
        let (preferUser, currentResourceVersion) = try resourceChannel.version()
        try await loadResource(url: Bundle.main.resourceURL!, channel: channel)

        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        if preferUser {
            try await reloadResources(channel: channel)
            logTrace(
                """
                外部资源版本：\(currentResourceVersion.title)
                更新时间：\(currentResourceVersion.last_updated)
                """)
        } else {
            logTrace(
                """
                内置资源版本：\(currentResourceVersion.title)
                更新时间：\(currentResourceVersion.last_updated)
                """)
            let url = documentsDirectory.appendingPathComponent("resource", isDirectory: true)
            try? FileManager.default.removeItem(at: url)
        }

        do {
            try await fetchOTAResource(channel: channel)
            let cachedBaseURL = documentsDirectory.appendingPathComponent("cache")
            try await loadResource(url: cachedBaseURL, channel: channel)
        } catch {
            logError("关卡数据获取失败: \(error.localizedDescription)")
        }

        #if DEBUG
        guard false else { return }
        #endif

        Task {
            do {
                let version = try await self.resourceChannel.latestVersion()
                if version > currentResourceVersion.last_updated {
                    logInfo("发现新资源版本：\(version)")
                    if autoResourceUpdate {
                        showResourceUpdate = true
                    }
                } else {
                    logInfo("资源已是最新版本")
                }
            } catch {
                logError("无法检查资源更新: \(error.localizedDescription)")
            }
        }
    }

    private func updateChannel(channel: MAAClientChannel) {
        for (index, task) in tasks.enumerated() {
            guard case .startup(var config) = task.task else {
                continue
            }

            config.client_type = channel

            tasks[index] = .init(id: task.id, task: .startup(config), enabled: task.enabled)
        }

        Task {
            try await loadResource(channel: channel)
        }
    }

    private func handleEarlyReturn(backTo: Status) {
        if status == .pending {
            status = backTo
        }
    }

    private static var userDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }

    private var instanceOptions: MAAInstanceOptions {
        [
            .TouchMode: touchMode.rawValue,
            .AdbLiteEnabled: (touchMode != .MacPlayTools && useAdbLite) ? "1" : "0",
        ]
    }

    private var adbPath: String {
        Bundle.main.url(forAuxiliaryExecutable: "adb")!.path
    }
}

// MARK: Daily Tasks

extension MAAViewModel {
    @discardableResult
    func applyDailyTaskCallback(_ update: DailyTaskCallbackUpdate, coreID: Int32?) -> Bool {
        guard let coreID, let context = dailyRunCoordinator.active,
              [.running, .stopping].contains(context.status),
              let id = taskIDMap[coreID],
              let index = dailyRunTasks?.firstIndex(where: { $0.id == id }),
              let original = dailyRunTasks?[index].task else { return false }
        do {
            let isCurrentProfile = context.profileID == dailyTaskProfile
            guard let updated = try DailyRunProfilePatchStore.apply(
                update, taskID: id, expected: original, profileID: context.profileID,
                currentTasks: isCurrentProfile ? tasks : nil, directory: tasksDirectory) else {
                logWarn("运行中的配置已被编辑，保留用户修改，未自动更新任务记录。")
                return false
            }
            // Only the callback field changes the frozen run view. Other edits
            // in the latest saved profile must not rewrite the running snapshot.
            if let snapshotUpdate = update.applying(to: original, expecting: original),
               let old = dailyRunTasks?[index] {
                dailyRunTasks?[index] = DailyTask(id: old.id, task: snapshotUpdate, enabled: old.enabled)
            }
            if isCurrentProfile {
                isApplyingDailyCallbackPatch = true
                tasks = updated
                isApplyingDailyCallbackPatch = false
            }
            return true
        } catch {
            logError(verbatim: "Run profile callback update failed: \(error.localizedDescription)")
            return false
        }
    }

    enum TaskStartResult: Equatable {
        case started
        case skipped
        case failed
    }

    @discardableResult
    func tryStartTasks() async -> Bool {
        await startDailyTasks() == .started
    }

    func startDailyTasks(origin: DailyRunOrigin = .manual, snapshot: DailyRunSnapshot? = nil, recoverGame: Bool = false, recoveryCurrent: (@MainActor () -> Bool)? = nil) async -> TaskStartResult {
        reconcileDailyRunStatus()
        guard canStartTasks else {
            return .skipped
        }

        do {
            try await beginTaskOperation()
        } catch {
            return .skipped
        }
        defer { isStartStopInFlight = false }

        do {
            logStore?.setDailyTasksDetailMode(.log)
            let snapshot = snapshot ?? DailyRunSnapshot(profileID: dailyTaskProfile, tasks: tasks)
            guard let runID = try dailyRunCoordinator.begin(profileID: snapshot.profileID, origin: origin) else { return .skipped }
            forceRecoveryJournalFailureRunID = nil
            dailyRunOutcome = .completed
            dailyRunTasks = snapshot.tasks
            if recoverGame { forceRecoveryInFlight = true }
            defer { if recoverGame && !forceRecoveryCleanupPending { forceRecoveryInFlight = false } }
            do {
                try dailyRunCoordinator.transition(.connecting, for: runID)
                try await startTasks(snapshot: snapshot, runID: runID, recoverGame: recoverGame, recoveryCurrent: recoveryCurrent)
                await finishDailyRunIfStopped(allowInFlight: true)
                return .started
            } catch {
                let recoveryCleanupFailed = error is ForcedRecoveryCleanupFailure
                let coreRunning = await handle?.running == true
                if recoveryCleanupFailed {
                    dailyRunOutcome = .failed
                    status = .busy
                    do { try dailyRunCoordinator.transition(.running, for: runID) }
                    catch {
                        forceRecoveryJournalFailureRunID = runID
                        logError(verbatim: "Daily run journal: \(error.localizedDescription)")
                    }
                    // Even a journal failure must not prevent safe eventual Core release.
                    waitForDailyRunCompletion(runID: runID)
                } else if coreRunning {
                    dailyRunOutcome = .failed
                    try dailyRunCoordinator.transition(.running, for: runID)
                    status = .busy
                } else {
                    let cleaned = await discardPreparedDailyTasks(for: runID) && !(error is ForcedRecoveryCleanupFailure)
                    try dailyRunCoordinator.finish(runID, outcome: error is CancellationError ? .cancelled : .failed, cleanupSucceeded: cleaned)
                    dailyRunTasks = nil
                }
                throw error
            }
        } catch {
            logError("StartTasksFailed: \(String(describing: error))")
            logInfo("CheckSettings")
            return .failed
        }
    }

    private func startTasks(snapshot: DailyRunSnapshot, runID: UUID, recoverGame: Bool = false, recoveryCurrent: (@MainActor () -> Bool)? = nil) async throws {
        var runTasks = snapshot.tasks
        status = .pending
        defer { handleEarlyReturn(backTo: .idle) }

        var firstStart = true
        for (index, task) in runTasks.enumerated() {
            guard case .startup(var config) = task.task else {
                continue
            }

            config.client_type = clientChannel
            runTasks[index] = .init(id: task.id, task: .startup(config), enabled: task.enabled)

            if touchMode == .MacPlayTools, task.enabled, config.start_game_enabled, firstStart {
                // Do not launch or switch a PlayCover game before recovery proves
                // the current session is safe. This mode must be configured without
                // automatic game launch for forced handoff.
                if recoverGame { throw ForcedRecoveryFailure.notReady }
                guard await startGame(client: config.client_type) else {
                    throw MAAError.gameStartFailed
                }
                firstStart = false
            }
        }

        for (index, task) in runTasks.enumerated() {
            guard case .closedown(var config) = task.task else {
                continue
            }

            config.client_type = clientChannel
            runTasks[index] = .init(id: task.id, task: .closedown(config), enabled: task.enabled)
        }

        dailyRunTasks = runTasks
        try await ensureHandle()
        try Task.checkCancellation()
        if recoverGame {
            try await recoverGameToHome(runID: runID, isCurrent: recoveryCurrent ?? { true })
            forceRecoveryInFlight = false
        }
        try Task.checkCancellation()

        for task in runTasks {
            try Task.checkCancellation()
            if recoverGame, recoveryCurrent?() == false { throw CancellationError() }
            guard task.enabled else { continue }

            if let coreID = try await handle?.appendTask(task.task) {
                taskIDMap[coreID] = task.id
            }
        }

        try Task.checkCancellation()
        if recoverGame, recoveryCurrent?() == false { throw CancellationError() }
        try dailyRunCoordinator.transition(.running, for: runID)
        try await startCoreTasks(recordDailyTaskStart: true)
    }

    /// Freeze the target at the occurrence, not after the previous run stops.
    /// Reject unsupported PlayCover auto-launch before stopping the old run.
    func forceRecoveryEligibility(snapshot: DailyRunSnapshot) -> @MainActor () -> Bool {
        let channel = clientChannel
        let address = connectionAddress
        let adb = adbPath
        let touch = touchMode
        let tools = toolsMode
        let gzip = useGzip
        let adbLite = useAdbLite
        let supportsRecovery = !(touch == .MacPlayTools && snapshot.tasks.contains { task in
            guard task.enabled, case .startup(let config) = task.task else { return false }
            return config.start_game_enabled
        })
        return { [weak self] in
            guard let self else { return false }
            return supportsRecovery && self.dailyTaskProfile == snapshot.profileID &&
                self.clientChannel == channel && self.connectionAddress == address && self.adbPath == adb &&
                self.touchMode == touch && self.toolsMode == tools && self.useGzip == gzip && self.useAdbLite == adbLite
        }
    }

    /// After an interrupted run, Core can be idle while the game is still in battle.
    /// Recover in an isolated task and require a real home-template callback before
    /// any of the user's tasks may be queued.
    private func recoverGameToHome(runID: UUID, isCurrent: @escaping @MainActor () -> Bool, timeout: TimeInterval = 300, cleanupTimeout: TimeInterval = 5) async throws {
        guard let handle, dailyRunCoordinator.active?.id == runID else { throw CancellationError() }
        let expires = Date().addingTimeInterval(timeout)
        do {
            // Native StartUp disables retries into a new fight, game launch and account switching.
            let startup = StartupConfiguration(client_type: clientChannel, start_game_enabled: false, account_name: "")
            let startupParams = try startup.params.jsonString()
            // The Home match is mandatory even when the navigation chain completes.
            let verify = try ["task_names": ["Home", "Home@QuickSwitch@ToHome@Entry", "Home@QuickSwitch@ToHome@Open"]].jsonString()
            func stopForRetry() async throws {
                try await handle.stop()
                let retryDeadline = min(expires, Date().addingTimeInterval(cleanupTimeout))
                while await handle.running {
                    try Task.checkCancellation()
                    guard Date() < retryDeadline, isCurrent(), dailyRunCoordinator.active?.id == runID else { throw ForcedRecoveryFailure.timedOut }
                    try await Task.sleep(for: .milliseconds(100))
                }
                try Task.checkCancellation()
                guard Date() < expires, isCurrent(), dailyRunCoordinator.active?.id == runID else { throw CancellationError() }
                forceRecovery = nil
            }
            do {
                try await runRecoveryTask(handle: handle, runID: runID, type: .StartUp,
                                          params: startupParams, chain: "StartUp", requiresHome: false, expires: expires, isCurrent: isCurrent)
            } catch ForcedRecoveryFailure.resultStalled {
                // Core may have reached the stage screen without reporting further
                // progress. Stop it first, then attempt verified home navigation.
                try await stopForRetry()
                do {
                    try await runRecoveryTask(handle: handle, runID: runID, type: .Custom,
                                              params: verify, chain: "Custom", requiresHome: true, expires: expires, isCurrent: isCurrent)
                    return
                } catch ForcedRecoveryFailure.notReady {
                    // Still on a result screen: stop and retry StartUp once.
                    try await stopForRetry()
                    do {
                        try await runRecoveryTask(handle: handle, runID: runID, type: .StartUp,
                                                  params: startupParams, chain: "StartUp", requiresHome: false, expires: expires, isCurrent: isCurrent)
                    } catch ForcedRecoveryFailure.resultStalled {
                        // A second result screen can clear after its click without
                        // StartUp recognizing the stage. Make one final home check.
                        try await stopForRetry()
                    }
                }
            }
            try await runRecoveryTask(handle: handle, runID: runID, type: .Custom,
                                      params: verify, chain: "Custom", requiresHome: true, expires: expires, isCurrent: isCurrent)
        } catch {
            var cleaned = false
            do {
                try await handle.stop()
                let cleanupDeadline = Date().addingTimeInterval(cleanupTimeout)
                repeat {
                    if await handle.running == false { cleaned = true; break }
                    // Cleanup must continue even when the caller was cancelled.
                    await Task.detached { try? await Task.sleep(for: .milliseconds(50)) }.value
                } while Date() < cleanupDeadline
            } catch { cleaned = false }
            guard cleaned else {
                // Keep Core and callback isolation until a later idle observation.
                forceRecoveryCleanupPending = true
                throw ForcedRecoveryCleanupFailure()
            }
            messageTask?.cancel()
            messageTask = nil
            self.handle = nil
            forceRecovery = nil
            throw error
        }
    }

    private func runRecoveryTask(handle: MAAHandle, runID: UUID, type: MAATaskType, params: String,
                                 chain: String, requiresHome: Bool, expires: Date, isCurrent: @escaping @MainActor () -> Bool) async throws {
        try Task.checkCancellation()
        guard isCurrent(), dailyRunCoordinator.active?.id == runID else { throw CancellationError() }
        guard Date() <= expires else { throw ForcedRecoveryFailure.timedOut }
        let taskID = try await handle.appendTask(type: type, params: params)
        try Task.checkCancellation()
        guard isCurrent(), dailyRunCoordinator.active?.id == runID else { throw CancellationError() }
        guard Date() <= expires else { throw ForcedRecoveryFailure.timedOut }
        forceRecovery = ForcedGameRecovery(taskID: taskID, chain: chain, requiresHome: requiresHome)
        try await handle.start()
        while Date() <= expires {
            try Task.checkCancellation()
            guard isCurrent(), dailyRunCoordinator.active?.id == runID, let state = forceRecovery else { throw CancellationError() }
            if state.failed { throw ForcedRecoveryFailure.notReady }
            if chain == "StartUp", let resultSince = state.resultSince, !state.completed,
               Date().timeIntervalSince(resultSince) >= 20 { throw ForcedRecoveryFailure.resultStalled }
            if state.completed && state.allCompleted {
                guard state.verified else { throw ForcedRecoveryFailure.notReady }
                if await handle.running == false {
                    try Task.checkCancellation()
                    guard Date() <= expires, isCurrent(), dailyRunCoordinator.active?.id == runID, forceRecovery?.taskID == taskID else { throw CancellationError() }
                    forceRecovery = nil
                    return
                }
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw ForcedRecoveryFailure.timedOut
    }

    private func initScheduledDailyTaskTimer() {
        scheduledDailyTaskTimers = {
            guard let serializedString = serializedScheduledDailyTaskTimers else {
                return []
            }

            return JSONHelper.json(from: serializedString, of: [DailyTaskTimer].self) ?? []
        }()
        $scheduledDailyTaskTimers
            .sink { [weak self] value in
                guard let self else {
                    return
                }

                guard let jsonString = try? value.jsonString() else {
                    print("Skip saving $scheduledDailyTaskTimers. Failed to serialize daily task timer.")
                    return
                }

                guard jsonString != self.serializedScheduledDailyTaskTimers else {
                    return
                }

                self.serializedScheduledDailyTaskTimers = jsonString
            }
            .store(in: &cancellables)
    }

    func appendNewTaskTimer() {
        scheduledDailyTaskTimers.append(DailyTaskTimer(id: UUID(), hour: 9, minute: 0, isEnabled: false))
    }
}

// MARK: Copilot

extension MAAViewModel {
    func startCopilot(type: MAATaskType, params: String) async throws {
        try await beginTaskOperation()
        defer { isStartStopInFlight = false }

        status = .pending
        defer { handleEarlyReturn(backTo: .idle) }

        try await ensureHandle()
        try await _ = handle?.appendTask(type: type, params: params)
        try await startCoreTasks()
    }
}

// MARK: Utility

extension MAAViewModel {
    func recognizeRecruit() async throws {
        try await beginTaskOperation()
        defer { isStartStopInFlight = false }

        status = .pending
        defer { handleEarlyReturn(backTo: .idle) }

        guard let params = try? recruitConfig.params.jsonString() else {
            return
        }

        try await ensureHandle()
        try await _ = handle?.appendTask(type: .Recruit, params: params)
        try await startCoreTasks()
    }

    func recognizeDepot() async throws {
        try await beginTaskOperation()
        defer { isStartStopInFlight = false }

        status = .pending
        defer { handleEarlyReturn(backTo: .idle) }

        try await ensureHandle()
        try await _ = handle?.appendTask(type: .Depot, params: "")
        try await startCoreTasks()
    }

    func recognizeVideo(video url: URL) async throws {
        try await beginTaskOperation()
        defer { isStartStopInFlight = false }

        status = .pending
        defer { handleEarlyReturn(backTo: .idle) }

        let config = VideoRecognitionConfiguration(filename: url.path)
        guard let params = config.params else {
            return
        }

        try await ensureHandle(requireConnect: false)
        try await _ = handle?.appendTask(type: .VideoRecognition, params: params)
        try await startCoreTasks()
    }

    func recognizeOperBox() async throws {
        try await beginTaskOperation()
        defer { isStartStopInFlight = false }

        status = .pending
        defer { handleEarlyReturn(backTo: .idle) }

        try await ensureHandle()
        try await _ = handle?.appendTask(type: .OperBox, params: "")
        try await startCoreTasks()
    }

    func gachaPoll(once: Bool) async throws {
        try await beginTaskOperation()
        defer { isStartStopInFlight = false }

        status = .pending
        defer { handleEarlyReturn(backTo: .idle) }

        try await ensureHandle()

        let name = once ? "GachaOnce" : "GachaTenTimes"
        let params = ["task_names": [name]]
        let data = try JSONSerialization.data(withJSONObject: params)
        let string = String(data: data, encoding: .utf8)

        try await _ = handle?.appendTask(type: .Custom, params: string ?? "")
        try await startCoreTasks()
    }

    func miniGame(name: String, params: Any? = nil) async throws {
        try await beginTaskOperation()
        defer { isStartStopInFlight = false }

        status = .pending
        defer { handleEarlyReturn(backTo: .idle) }

        try await ensureHandle()

        let params = ["task_names": [name], "params": params]
        let data = try JSONSerialization.data(withJSONObject: params)
        let string = String(data: data, encoding: .utf8)

        try await _ = handle?.appendTask(type: .Custom, params: string ?? "")
        try await startCoreTasks()
    }
}

// MARK: - Prevent Sleep

extension MAAViewModel {
    func switchAwakeGuard(_ newValue: Status) {
        switch newValue {
        case .busy, .pending:
            wakeupSystem()
            enableAwake()
        case .idle:
            disableAwake()
        }
    }

    // wakes the system from asleep
    private func wakeupSystem() {
        guard wakeupAssertionID == nil else { return }
        var assertionID: IOPMAssertionID = 0
        let name = "MAA is starting up, waking up the system"
        let result = IOPMAssertionDeclareUserActivity(name as CFString, kIOPMUserActiveLocal, &assertionID)
        if result == kIOReturnSuccess {
            wakeupAssertionID = assertionID
        }
    }

    // keeps the system from sleeping during tasks
    private func enableAwake() {
        guard awakeAssertionID == nil else { return }
        var assertionID: IOPMAssertionID = 0
        let name = "MAA is running; sleep is diabled."
        let properties =
            [
                kIOPMAssertionTypeKey: kIOPMAssertionTypeNoDisplaySleep as CFString,
                kIOPMAssertionNameKey: name as CFString,
                kIOPMAssertionLevelKey: UInt32(kIOPMAssertionLevelOn),
            ] as [String: Any]
        let result = IOPMAssertionCreateWithProperties(properties as CFDictionary, &assertionID)
        if result == kIOReturnSuccess {
            awakeAssertionID = assertionID
        }
    }

    private nonisolated static func releaseAssertion(_ assertionID: IOPMAssertionID?) {
        if let assertionID {
            let result = IOPMAssertionRelease(assertionID)
            if result != kIOReturnSuccess {
                // TODO: Replace with OSLog
                print("Failed to release PM assertion (\(result))")
            }
        }
    }

    private func disableAwake() {
        Self.releaseAssertion(awakeAssertionID)
        Self.releaseAssertion(wakeupAssertionID)
        self.awakeAssertionID = nil
        self.wakeupAssertionID = nil
    }
}

// MARK: - MaaTools Client

extension MAAViewModel {
    nonisolated func startGame(client: MAAClientChannel) async -> Bool {
        let appBundle = URL(fileURLWithPath: "/Users")
            .appendingPathComponent(NSUserName())
            .appendingPathComponent("Library")
            .appendingPathComponent("Containers")
            .appendingPathComponent("io.playcover.PlayCover")
            .appendingPathComponent("Applications")
            .appendingPathComponent(client.appBundleID)
            .appendingPathExtension("app")

        do {
            try await NSWorkspace.shared.openApplication(at: appBundle, configuration: .init())
            let client = await MaaToolClient(address: connectionAddress)
            return client != nil
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain, nsError.code == 260 {
                await logError("无法找到游戏文件: \(client.appBundleID)")
            }
            return false
        }
    }

    func stopGame() async throws {
        guard let client = await MaaToolClient(address: connectionAddress) else { return }
        try await client.terminate()
    }
}

private enum ForcedRecoveryFailure: Error { case notReady, timedOut, resultStalled }
private struct ForcedRecoveryCleanupFailure: Error {}
