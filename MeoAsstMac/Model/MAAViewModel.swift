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

    private var wakeupAssertionID: UInt32?
    private var awakeAssertionID: UInt32?
    private var handle: MAAHandle?
    private var cancellables = Set<AnyCancellable>()

    // 核心回调可能在异步操作返回前重置 status，独立标记防止入口重叠。
    @Published private(set) var isStartStopInFlight = false
    private var taskCompletionGeneration = UInt64(0)
    private var dailyCompletionTask: Task<Void, Never>?
    private var dailyFinishAttemptedRunID: UUID?

    let dailyRunCoordinator = DailyRunCoordinator(journalURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("DailyRunJournal.json"))
    private var dailyRunOutcome = DailyRunOutcome.completed
    private(set) var dailyRunTasks: [DailyTask]?
    private(set) var isApplyingDailyCallbackPatch = false
    let hookSettings = HookSettingsStore()
    private var runHookConfiguration = HookConfiguration()
    private var dailyStartCancelled = false
    private var activeHookTask: Task<HookResult, Error>?
    private var runTerminationDeadline: Date?
    @Published private(set) var hookTestResult: String?
    @Published private(set) var isTestingHook = false

    var canStartTasks: Bool {
        status == .idle && !isStartStopInFlight && dailyRunCoordinator.active == nil && !isTestingHook
    }

    private func beginTaskOperation(requiresIdle: Bool = true) async throws {
        reconcileDailyRunStatus()
        guard !isStartStopInFlight else {
            logError("当前正在启动或停止任务，请稍后重试。")
            throw MAAError.taskOperationInProgress
        }
        guard !requiresIdle || (status == .idle && dailyRunCoordinator.active == nil && !isTestingHook) else {
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

    struct DailyTaskTimer: Codable {
        let id: UUID
        var hour: Int
        var minute: Int
        var isEnabled: Bool
    }

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
    }

    func ensureHandle(requireConnect: Bool = true, clearLogs: Bool = true) async throws {
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

        if clearLogs { logStore?.clearLogs() }
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
        if let context = dailyRunCoordinator.active,
           [.preparing, .preHook, .connecting].contains(context.status) {
            dailyStartCancelled = true
            dailyRunOutcome = .cancelled
            activeHookTask?.cancel()
            return
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
        if let active = dailyRunCoordinator.active,
           active.status == .postHook || dailyFinishAttemptedRunID == active.id {
            status = .pending
            return
        }
        dailyCompletionTask?.cancel()
        guard let runID = dailyRunCoordinator.active?.id else { return }
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

    private func reconcileDailyRunStatus() {
        if status == .idle, let phase = dailyRunCoordinator.active?.status {
            status = phase == .running ? .busy : .pending
        }
    }

    func markDailyRunFailed() {
        if dailyRunCoordinator.active != nil {
            dailyRunOutcome = .failed
            Task { await finishDailyRunIfStopped() }
        }
    }

    /// A stopped core can still own successfully appended tasks from a failed preparation.
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
              [.running, .stopping].contains(context.status) else { return false }
        guard await handle?.running != true,
              (allowInFlight || !Task.isCancelled),
              (allowInFlight || !isStartStopInFlight),
              dailyRunCoordinator.active?.id == context.id,
              let currentStatus = dailyRunCoordinator.active?.status,
              [.running, .stopping].contains(currentStatus) else { return false }
        // A persistence or hook failure must not spin and repeatedly write the journal.
        guard dailyFinishAttemptedRunID != context.id else { return true }
        dailyFinishAttemptedRunID = context.id
        await finishDailyRun(context.id, outcome: dailyRunOutcome)
        return true
    }

    private func finishDailyRun(_ id: UUID, outcome: DailyRunOutcome, preparationCleanupSucceeded: Bool = true) async {
        guard let context = dailyRunCoordinator.active, context.id == id, context.status != .postHook else { return }
        do {
            try dailyRunCoordinator.transition(.postHook, for: id)
            status = .pending
            var cleanupSucceeded = preparationCleanupSucceeded
            if runHookConfiguration.enabled, let command = runHookConfiguration.after {
                do {
                    let result = try await executeHook(command, context: context, outcome: outcome, cancellable: false)
                    cleanupSucceeded = result.succeeded && cleanupSucceeded
                } catch {
                    cleanupSucceeded = false
                    logError(verbatim: "Post-run script: \(error.localizedDescription)")
                }
            }
            try dailyRunCoordinator.finish(id, outcome: outcome, cleanupSucceeded: cleanupSucceeded)
            dailyRunTasks = nil
            status = .idle
            if !cleanupSucceeded { logError("后置清理失败，请检查脚本输出并手动恢复设备设置") }
        } catch {
            status = .pending
            logError(verbatim: "Daily run journal: \(error.localizedDescription)")
        }
    }

    private func executeHook(_ command: HookCommand, context: RunContext, outcome: DailyRunOutcome?, cancellable: Bool = true) async throws -> HookResult {
        let directory = Self.userDirectory.appendingPathComponent("RunHooks", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuredTimeout = TimeInterval(runHookConfiguration.timeoutSeconds)
        let timeout = runTerminationDeadline.map { min(configuredTimeout, $0.timeIntervalSinceNow) } ?? configuredTimeout
        guard timeout > 0 else { throw CancellationError() }
        let adb = adbPath
        let task = Task { try await HookRunner().run(command: command, context: context, outcome: outcome,
                                                     adbPath: adb, workingDirectory: directory, timeout: timeout) }
        activeHookTask = task
        defer { activeHookTask = nil }
        let result: HookResult
        if cancellable {
            result = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
        } else {
            result = try await task.value
        }
        logInfo(verbatim: "Script run=\(context.id) result=\(outcome?.rawValue ?? "preparing") exit=\(result.exitCode) timeout=\(result.timedOut) cancelled=\(result.cancelled)")
        if !result.stdout.isEmpty { logTrace(verbatim: result.stdout) }
        if !result.stderr.isEmpty { logWarn(verbatim: result.stderr) }
        if result.stdoutTruncated || result.stderrTruncated { logWarn("脚本输出已截断（每个输出流最多 32 KiB）") }
        return result
    }

    func testHook(_ command: HookCommand) async {
        guard canStartTasks, !isTestingHook else { return }
        isTestingHook = true
        defer { isTestingHook = false }
        runHookConfiguration = hookSettings.configuration
        let context = RunContext(id: UUID(), origin: .manual, profileID: dailyTaskProfile, status: .preHook, startedAt: .now)
        do {
            let result = try await executeHook(command, context: context, outcome: nil)
            hookTestResult = "Exit \(result.exitCode)\n\(result.stdout)\n\(result.stderr)"
        } catch { hookTestResult = error.localizedDescription }
    }

    func recoverInterruptedRun() async {
        guard canStartTasks, let context = dailyRunCoordinator.lastTerminal,
              let command = hookSettings.configuration.after else { return }
        isTestingHook = true
        defer { isTestingHook = false }
        runHookConfiguration = hookSettings.configuration
        do {
            let result = try await executeHook(command, context: context, outcome: .interrupted)
            try dailyRunCoordinator.recordRecovery(for: context.id, succeeded: result.succeeded)
            hookTestResult = "Exit \(result.exitCode)\n\(result.stdout)\n\(result.stderr)"
        } catch { hookTestResult = error.localizedDescription }
    }

    func prepareForTermination(timeout: TimeInterval = 65) async {
        let deadline = Date.now.addingTimeInterval(max(0, timeout))
        runTerminationDeadline = deadline
        if isTestingHook {
            activeHookTask?.cancel()
            if let task = activeHookTask { _ = try? await task.value }
        }
        guard dailyRunCoordinator.active != nil else { return }
        Task { try? await self.stop() }
        while dailyRunCoordinator.active != nil, Date.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        if dailyRunCoordinator.active != nil {
            // An allowed 300-second hook must not survive a shorter app-exit
            // deadline. Cancellation waits for TERM/KILL and group reaping.
            activeHookTask?.cancel()
            if let task = activeHookTask { _ = try? await task.value }
            let settleDeadline = Date.now.addingTimeInterval(3)
            while dailyRunCoordinator.active != nil, Date.now < settleDeadline {
                activeHookTask?.cancel()
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        if dailyRunCoordinator.active != nil { logError("退出前清理未完成，下次启动将报告中断记录") }
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

    func startDailyTasks(origin: DailyRunOrigin = .manual, snapshot: DailyRunSnapshot? = nil) async -> TaskStartResult {
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
            dailyRunTasks = snapshot.tasks
            dailyRunOutcome = .completed
            dailyStartCancelled = false
            runHookConfiguration = hookSettings.configuration
            do {
                status = .pending
                logStore?.clearLogs()
                if runHookConfiguration.enabled, let command = runHookConfiguration.before {
                    try dailyRunCoordinator.transition(.preHook, for: runID)
                    let result = try await executeHook(command, context: dailyRunCoordinator.active!, outcome: nil)
                    guard result.succeeded else { throw CancellationError() }
                }
                if dailyStartCancelled { throw CancellationError() }
                try Task.checkCancellation()
                try dailyRunCoordinator.transition(.connecting, for: runID)
                try await startTasks(snapshot: snapshot, runID: runID)
                await finishDailyRunIfStopped(allowInFlight: true)
                return .started
            } catch {
                if await handle?.running == true {
                    dailyRunOutcome = .failed
                    try dailyRunCoordinator.transition(.running, for: runID)
                    status = .busy
                } else {
                    let cleaned = await discardPreparedDailyTasks(for: runID)
                    await finishDailyRun(runID, outcome: dailyStartCancelled || Task.isCancelled ? .cancelled : .failed,
                                         preparationCleanupSucceeded: cleaned)
                }
                throw error
            }
        } catch {
            logError("StartTasksFailed: \(String(describing: error))")
            logInfo("CheckSettings")
            return .failed
        }
    }

    private func startTasks(snapshot: DailyRunSnapshot, runID: UUID) async throws {
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
        try await ensureHandle(clearLogs: false)
        if dailyStartCancelled { throw CancellationError() }
        try Task.checkCancellation()

        for task in runTasks {
            guard task.enabled else { continue }

            if let coreID = try await handle?.appendTask(task.task) {
                taskIDMap[coreID] = task.id
            }
        }

        if dailyStartCancelled { throw CancellationError() }
        try Task.checkCancellation()
        try dailyRunCoordinator.transition(.running, for: runID)
        try await startCoreTasks(recordDailyTaskStart: true)
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
