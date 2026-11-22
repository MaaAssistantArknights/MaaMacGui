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
    private var clientQueue: Task<Void, Error>?
    private(set) var runningClient: MAAClientChannel?
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

    init(loadDailyTasks: Bool = true) {
        guard loadDailyTasks else { return }
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
    func initialize(for client: MAAClientChannel? = nil) async throws {
        status = .pending
        try await MAAProvider.shared.setUserDirectory(path: Self.userDirectory.path)
        if useWebGPU {
            try await MAAProvider.shared.setStaticOption(key: 2, value: "webgpu:0")
        }
        try await loadResource(channel: client ?? clientChannel, checkForUpdates: client == nil)
        status = .idle
    }

    func ensureHandle(requireConnect: Bool = true) async throws {
        guard clientQueue == nil else { throw MAAError.handleNotRunning }
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
        taskStatus.removeAll()

        if requireConnect, let handle { try await connect(handle) }
    }

    func connect(_ handle: MAAHandle) async throws {
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

        try await handle.connect(adbPath: adbPath, address: connectionAddress, profile: connectionProfile)
        logTrace("Running")
    }

    func stop() async throws {
        if let clientQueue {
            clientQueue.cancel()
            _ = await clientQueue.result
            return
        }
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
        let files = [
            (path: "resource/tasks.json", name: "resource/tasks/tasks.json"),
            (path: "gui/StageActivityV2.json", name: "gui/StageActivityV2.json"),
        ]
        try await withThrowingTaskGroup(of: Void.self) { group in
            if channel.isGlobal {
                group.addTask { try await Self.fetchClientOTAResource(channel) }
            }
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

    private nonisolated static func fetchClientOTAResource(_ channel: MAAClientChannel) async throws {
        let base = "resource/global/\(channel.rawValue)/resource/"
        try await OTAFetcher().download(path: base + "tasks.json", name: base + "tasks/tasks.json")
    }

    /// Load resources from bundled, user, and remote resources.
    ///
    /// Should be the outermost call to load resources.
    private func loadResource(channel: MAAClientChannel, checkForUpdates: Bool = true) async throws {
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
            if checkForUpdates {
                let url = documentsDirectory.appendingPathComponent("resource", isDirectory: true)
                try? FileManager.default.removeItem(at: url)
            }
        }

        let cachedBaseURL = documentsDirectory.appendingPathComponent("cache")
        if !checkForUpdates {
            if FileManager.default.fileExists(atPath: cachedBaseURL.appendingPathComponent("resource").path) {
                try await loadResource(url: cachedBaseURL, channel: channel)
            }
            return
        }
        do {
            try await fetchOTAResource(channel: channel)
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

    var instanceOptions: MAAInstanceOptions {
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
        guard status == .idle, clientQueue == nil else { return }
        do {
            logStore?.setDailyTasksDetailMode(.log)
            try await startTasks()
        } catch is CancellationError {
            logTrace(.stopped)
        } catch let error as ClientTaskRunner.Failure {
            logError(verbatim: error.description)
        } catch {
            logError("StartTasksFailed: \(String(describing: error))")
            logInfo("CheckSettings")
        }
    }

    private func startTasks() async throws {
        if tasks.contains(where: { entry in
            guard entry.enabled, case .startup(let config) = entry.task else { return false }
            return config.clientOverride != nil
        }) {
            let batches = ClientTaskBatch.batches(for: tasks, defaultClient: clientChannel)
            taskStatus.removeAll()
            logStore?.clearLogs()
            if touchMode == .MacPlayTools,
                let id = batches.first(where: { $0.client == .Bilibili })?.tasks.first?.id,
                let index = tasks.firstIndex(id: id)
            {
                taskStatus[id] = .failure
                let row = "#\(index + 1)"
                let reason = String(localized: "PlayCover 不支持 \(MAAClientChannel.Bilibili.description)")
                throw ClientTaskRunner.Failure(String(localized: "\(row)：\(reason)"))
            }
            status = .busy
            logStore?.taskStartTime = .now
            let queue = Task {
                var refreshedClients: Set<MAAClientChannel> = [clientChannel]
                var finishedTasks = [UUID]()
                for batch in batches {
                    try Task.checkCancellation()
                    runningClient = batch.client
                    taskIDMap.removeAll()
                    logInfo(verbatim: batch.client.description)
                    if batch.client.isGlobal, refreshedClients.insert(batch.client).inserted {
                        do { try await Self.fetchClientOTAResource(batch.client) }
                        catch { logError("关卡数据获取失败: \(error.localizedDescription)") }
                    }
                    try Task.checkCancellation()
                    let completed = try await ClientTaskRunner.run(batch) { event in
                        switch event {
                        case .task(let coreID, let id): taskIDMap[coreID] = id
                        case .message(let message): processMessage(message)
                        }
                    }
                    finishedTasks += completed.compactMap { taskIDMap[$0] }
                }
                logDailyTaskCompletion(finishedTasks)
            }
            clientQueue = queue
            let result = await queue.result
            clientQueue = nil
            runningClient = nil
            for (id, state) in taskStatus where state == .running {
                switch result {
                case .failure(let error) where !(error is CancellationError): taskStatus[id] = .failure
                default: taskStatus[id] = .cancel
                }
            }
            if status != .idle { resetStatus() }
            try result.get()
            return
        }
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

        try await ensureHandle()

        for task in tasks {
            guard task.enabled else { continue }

            if let coreID = try await handle?.appendTask(task.task) {
                taskIDMap[coreID] = task.id
            }
        }

        try await handle?.start()
        logStore?.taskStartTime = .now

        status = .busy
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
    func preparePlayCover(client: MAAClientChannel, launch: Bool) async throws {
        guard client != .Bilibili else {
            throw ClientTaskRunner.Failure(String(localized: "PlayCover 不支持 \(client.description)"))
        }
        let expected = client.appBundleID
        func mismatch(_ current: String) -> ClientTaskRunner.Failure {
            NSLog("PlayCover bundle mismatch: %@ (expected %@)", current, expected)
            return ClientTaskRunner.Failure(String(localized: "客户端不匹配，请切换到\(client.description)"))
        }
        let portDeadline = ContinuousClock.now + .seconds(6)
        while let current = try await MaaToolsClient.runningBundle(at: connectionAddress) {
            if current == expected { return }
            guard launch, ContinuousClock.now < portDeadline else {
                throw mismatch(current)
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        guard launch else { throw MaaCoreError.connectFailed }
        let game = try await NSWorkspace.shared.openApplication(at: client.playCoverURL, configuration: .init())
        let deadline = ContinuousClock.now + .seconds(45)
        while !game.isTerminated, ContinuousClock.now < deadline {
            if let current = try await MaaToolsClient.runningBundle(at: connectionAddress) {
                guard current == expected else {
                    throw mismatch(current)
                }
                return
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw MAAError.gameStartFailed
    }

    nonisolated func startGame(client: MAAClientChannel) async -> Bool {
        do {
            try await NSWorkspace.shared.openApplication(at: client.playCoverURL, configuration: .init())
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
