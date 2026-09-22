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
        case skipped
        case success
    }

    @Published var taskStatus: [UUID: TaskStatus] = [:]

    /// 一个条目占用的全部 core 任务 id 及其状态。
    ///
    /// 条目可以拆成多个 core 任务（「更新数据」= 干员识别 + 仓库识别），
    /// 条目状态按 WPF 口径合成：任一子任务失败即失败，全部完成才算完成。
    private var taskSubtasks = [UUID: [Int32]]()
    private var subtaskStatuses = [Int32: TaskStatus]()

    /// 更新条目状态，`coreID` 为对应的 core 任务 id
    func updateTaskStatus(_ status: TaskStatus, coreID: Int32?) {
        guard let coreID, let id = taskIDMap[coreID] else {
            return
        }

        // 先记状态再合成：子任务的完成顺序不确定（一图流拉取可能先于同条目的 core 子任务结束）
        subtaskStatuses[coreID] = status

        let subtasks = taskSubtasks[id] ?? [coreID]
        guard subtasks.count > 1 else {
            taskStatus[id] = status
            return
        }

        if subtasks.contains(where: { subtaskStatuses[$0] == .failure }) {
            taskStatus[id] = .failure
        } else if subtasks.allSatisfy({ subtaskStatuses[$0] == .success }) {
            taskStatus[id] = .success
        } else if subtasks.contains(where: { subtaskStatuses[$0] == .cancel }) {
            taskStatus[id] = .cancel
        } else {
            taskStatus[id] = .running
        }
    }

    /// 记录条目占用的 core 任务 id
    func addTaskIDs(_ coreTaskIDs: [Int32], for id: UUID) {
        guard !coreTaskIDs.isEmpty else {
            return
        }

        for coreTaskID in coreTaskIDs {
            taskIDMap[coreTaskID] = id
        }
        taskSubtasks[id, default: []].append(contentsOf: coreTaskIDs)
    }

    /// 前端子任务（不占 core 任务，如「更新数据」中从一图流获取的干员识别）的哨兵 id。
    ///
    /// core 任务 id 由 `AsstAppendTask` 从 1 起分配，负数不会与之冲突；逐个递减发放，
    /// 保证同一轮里多个条目的子任务 id 互不覆盖。
    private var nextFrontendSubtaskID: Int32 = -1

    /// 把一个不占 core 任务的前端子任务登记到条目上，返回它的哨兵 id。
    ///
    /// 登记后该子任务与 core 子任务共用 `updateTaskStatus` 的聚合语义：任一失败即条目失败，
    /// 全部成功才算条目成功。
    private func addFrontendSubtask(for id: UUID) -> Int32 {
        let subtaskID = nextFrontendSubtaskID
        nextFrontendSubtaskID -= 1
        addTaskIDs([subtaskID], for: id)
        return subtaskID
    }

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

    // MARK: - Third-Party Service Settings

    /// 一图流 OpenAPI Token，鉴权方式为请求头 Authorization 直接携带
    @AppStorage("MAAYituliuOpenApiToken") var yituliuOpenApiToken = ""

    /// 干员识别改为从一图流 OpenAPI 获取（不再连接模拟器截图识别）
    @AppStorage("MAAOperBoxUseYituliuApi") var enableOperBoxYituliuApi = false

    // MARK: - User Data Update

    @AppStorage("MAALastDepotSyncTime") private var lastDepotSyncTimeInterval: Double = 0
    @AppStorage("MAALastOperBoxSyncTime") private var lastOperBoxSyncTimeInterval: Double = 0

    /// 上次仓库同步时间，无记录时为 nil
    ///
    /// `@AppStorage` 不参与 `ObservableObject` 的发布，改写后手动通知界面刷新（设置页要展示时间）。
    var lastDepotSyncTime: Date? {
        get {
            lastDepotSyncTimeInterval > 0 ? Date(timeIntervalSince1970: lastDepotSyncTimeInterval) : nil
        }
        set {
            lastDepotSyncTimeInterval = newValue?.timeIntervalSince1970 ?? 0
            objectWillChange.send()
        }
    }

    /// 上次干员同步时间，无记录时为 nil
    var lastOperBoxSyncTime: Date? {
        get {
            lastOperBoxSyncTimeInterval > 0 ? Date(timeIntervalSince1970: lastOperBoxSyncTimeInterval) : nil
        }
        set {
            lastOperBoxSyncTimeInterval = newValue?.timeIntervalSince1970 ?? 0
            objectWillChange.send()
        }
    }

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
        try await loadResource(channel: clientChannel)
        status = .idle
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
            throw MAAError.handleNotRunning
        }

        logStore?.clearLogs()
        taskIDMap.removeAll()
        taskSubtasks.removeAll()
        subtaskStatuses.removeAll()
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

    func stop() async throws {
        status = .pending
        defer { handleEarlyReturn(backTo: .busy) }

        try await handle?.stop()
        status = .idle
    }

    func resetStatus() {
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
    func tryStartTasks() async {
        do {
            logStore?.setDailyTasksDetailMode(.log)
            try await startTasks()
        } catch {
            logError("StartTasksFailed: \(String(describing: error))")
            logInfo("CheckSettings")
        }
    }

    private func startTasks() async throws {
        status = .pending
        defer { handleEarlyReturn(backTo: .idle) }

        var firstStart = true
        for (index, task) in tasks.enumerated() {
            guard case .startup(var config) = task.task else {
                continue
            }

            config.client_type = clientChannel
            tasks[index] = .init(id: task.id, task: .startup(config), enabled: task.enabled)

            if touchMode == .MacPlayTools, task.enabled, config.start_game_enabled, firstStart {
                guard await startGame(client: config.client_type) else {
                    throw MAAError.gameStartFailed
                }
                firstStart = false
            }
        }

        for (index, task) in tasks.enumerated() {
            guard case .closedown(var config) = task.task else {
                continue
            }

            config.client_type = clientChannel
            tasks[index] = .init(id: task.id, task: .closedown(config), enabled: task.enabled)
        }

        let plans = planTasks()
        // 一图流子任务不依赖模拟器：本轮没有任何 core 任务时（例如「更新数据」仅勾选干员识别
        // 且从一图流获取）不必连接，同队列还有 core 任务时连接仍先于它们的执行。
        try await ensureHandle(requireConnect: plans.contains { $0.coreTask != nil })

        var hasCoreTask = false
        for plan in plans {
            if plan.operBoxFromYituliu {
                let subtaskID = addFrontendSubtask(for: plan.id)
                Task { await syncOperBoxFromYituliu(subtaskID: subtaskID) }
            }

            guard let coreTask = plan.coreTask else {
                continue
            }

            let coreTaskIDs = try await handle?.appendTask(coreTask) ?? []
            addTaskIDs(coreTaskIDs, for: plan.id)
            hasCoreTask = hasCoreTask || !coreTaskIDs.isEmpty
        }

        guard hasCoreTask else {
            // 本轮没有任何 core 任务（例如「更新数据」仅勾选干员识别且从一图流获取），不启动 core，
            // 条目状态由各自分支标记
            return
        }

        try await handle?.start()
        logStore?.taskStartTime = .now

        status = .busy
    }

    /// 本轮要执行的一个队列条目。
    private struct TaskPlan {
        let id: UUID
        /// 交给 core 追加的任务；「更新数据」剔除一图流子项后 core 无事可做时为 nil
        let coreTask: MAATask?
        /// 干员识别改由一图流 OpenAPI 拉取（不占 core 任务，也不需要模拟器连接）
        let operBoxFromYituliu: Bool
    }

    /// 规划本轮任务：按触发间隔与一图流开关决定子项去留，只读状态、不触碰 core。
    ///
    /// 「更新数据」是前端伪任务，规划的产物既决定要追加哪些 core 任务，也决定本轮是否需要模拟器连接。
    private func planTasks() -> [TaskPlan] {
        var plans = [TaskPlan]()

        for task in tasks {
            guard task.enabled else { continue }

            guard case .userdataupdate(var config) = task.task else {
                plans.append(TaskPlan(id: task.id, coreTask: task.task, operBoxFromYituliu: false))
                continue
            }

            let interval = config.triggerInterval
            let operBoxDue =
                config.updateOperBox && interval.isDue(lastSyncTime: lastOperBoxSyncTime, channel: clientChannel)
            let depotDue = config.updateDepot && interval.isDue(lastSyncTime: lastDepotSyncTime, channel: clientChannel)

            guard operBoxDue || depotDue else {
                if config.updateOperBox || config.updateDepot {
                    logInfo("距上次同步未达到「\(interval.description)」触发间隔")
                } else {
                    logInfo("「干员识别」和「仓库识别」均未勾选")
                }
                taskStatus[task.id] = .skipped
                continue
            }

            var operBoxFromYituliu = false
            if operBoxDue, enableOperBoxYituliuApi {
                guard !yituliuOpenApiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    logError("请先填写 Token")
                    taskStatus[task.id] = .failure
                    continue
                }

                operBoxFromYituliu = true
            }

            config.updateOperBox = operBoxDue && !operBoxFromYituliu
            config.updateDepot = depotDue

            let hasCoreSubtasks = config.updateOperBox || config.updateDepot
            plans.append(
                TaskPlan(
                    id: task.id, coreTask: hasCoreSubtasks ? .userdataupdate(config) : nil,
                    operBoxFromYituliu: operBoxFromYituliu))
        }

        return plans
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

// MARK: User Data Update

extension MAAViewModel {
    /// 从一图流 OpenAPI 拉取干员练度数据，拉取结束后写日志并更新任务条目状态。
    /// 拉取是后台并行的，只在结束时输出日志，避免与队列启动日志交错。
    ///
    /// 状态写回走 `updateTaskStatus`：一图流子任务与同条目的 core 子任务（如仓库识别）按同一口径合成。
    private func syncOperBoxFromYituliu(subtaskID: Int32) async {
        let success = await fetchOperBoxFromYituliu()
        if success {
            logInfo("干员识别完成（一图流）")
        }
        updateTaskStatus(success ? .success : .failure, coreID: subtaskID)
    }

    /// 从一图流 OpenAPI 拉取干员练度数据并按识别结果填充，不依赖模拟器连接。
    ///
    /// 拉取失败只报错不回退 core 本地识别：开关开着是用户显式选择，静默回退会突然要求连接模拟器。
    /// 拉取成功后才替换旧识别数据，失败时保留。
    private func fetchOperBoxFromYituliu() async -> Bool {
        let token = yituliuOpenApiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            logError("请先填写 Token")
            return false
        }

        let (result, data) = await YituliuApiService.operatorInfo(token: token)
        guard result == .valid, let data else {
            logError("从一图流获取失败：\(result.description)")
            return false
        }

        let operBox = MAAOperBox(yituliu: data, channel: clientChannel)
        guard !operBox.own_opers.isEmpty else {
            // 两种空结果：账号未绑定或未导入练度（接口返回空列表），本地干员表加载失败
            // （battle_data.json 缺失或解码失败，全部干员被跳过）。此时都保留本地识别数据。
            if MAAOperBox.hasLocalOperatorTable {
                logError("Token 对应的一图流账号暂无干员练度数据，已保留本地识别结果")
            } else {
                logError("本地干员数据缺失，无法补全一图流练度数据，已保留本地识别结果")
            }
            return false
        }

        logStore?.setOperBox(operBox)
        lastOperBoxSyncTime = .now
        return true
    }
}

// MARK: Copilot

extension MAAViewModel {
    func startCopilot(type: MAATaskType, params: String) async throws {
        status = .pending
        defer { handleEarlyReturn(backTo: .idle) }

        try await ensureHandle()
        try await _ = handle?.appendTask(type: type, params: params)
        try await handle?.start()

        status = .busy
    }
}

// MARK: Utility

extension MAAViewModel {
    func recognizeRecruit() async throws {
        status = .pending
        defer { handleEarlyReturn(backTo: .idle) }

        guard let params = try? recruitConfig.params.jsonString() else {
            return
        }

        try await ensureHandle()
        try await _ = handle?.appendTask(type: .Recruit, params: params)
        try await handle?.start()

        status = .busy
    }

    func recognizeDepot() async throws {
        status = .pending
        defer { handleEarlyReturn(backTo: .idle) }

        try await ensureHandle()
        try await _ = handle?.appendTask(type: .Depot, params: "")
        try await handle?.start()

        status = .busy
    }

    func recognizeVideo(video url: URL) async throws {
        status = .pending
        defer { handleEarlyReturn(backTo: .idle) }

        let config = VideoRecognitionConfiguration(filename: url.path)
        guard let params = config.params else {
            return
        }

        try await ensureHandle(requireConnect: false)
        try await _ = handle?.appendTask(type: .VideoRecognition, params: params)
        try await handle?.start()

        status = .busy
    }

    func recognizeOperBox() async throws {
        status = .pending
        defer { handleEarlyReturn(backTo: .idle) }

        if enableOperBoxYituliuApi {
            // 一图流模式不占 core 任务：拉取本身就是识别，结束后由状态机回落到 idle，
            // 失败（含 Token 为空）由拉取函数写日志提示并保留旧数据
            if await fetchOperBoxFromYituliu() {
                logInfo("干员识别完成（一图流）")
            }
            return
        }

        try await ensureHandle()
        try await _ = handle?.appendTask(type: .OperBox, params: "")
        try await handle?.start()

        status = .busy
    }

    func gachaPoll(once: Bool) async throws {
        status = .pending
        defer { handleEarlyReturn(backTo: .idle) }

        try await ensureHandle()

        let name = once ? "GachaOnce" : "GachaTenTimes"
        let params = ["task_names": [name]]
        let data = try JSONSerialization.data(withJSONObject: params)
        let string = String(data: data, encoding: .utf8)

        try await _ = handle?.appendTask(type: .Custom, params: string ?? "")
        try await handle?.start()

        status = .busy
    }

    func miniGame(name: String, params: Any? = nil) async throws {
        status = .pending
        defer { handleEarlyReturn(backTo: .idle) }

        try await ensureHandle()

        let params = ["task_names": [name], "params": params]
        let data = try JSONSerialization.data(withJSONObject: params)
        let string = String(data: data, encoding: .utf8)

        try await _ = handle?.appendTask(type: .Custom, params: string ?? "")
        try await handle?.start()

        status = .busy
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
