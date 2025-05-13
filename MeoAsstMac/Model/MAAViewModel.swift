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

    @Published var logs = [MAALog]()
    @Published var trackTail = false
    let fileLogger: FileLogger

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
    @Published var dailyTasksDetailMode: DailyTasksDetailMode = .log

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

    // MARK: - Copilot

    enum CopilotDetailMode: Hashable {
        case copilotConfig
        case log
    }

    @Published var copilot: CopilotConfiguration?
    @Published var showImportCopilot = false
    @Published var copilotDetailMode: CopilotDetailMode = .log

    @Published var copilots = Set<URL>()
    @Published var downloading = false
    @Published var selectedCopilotURL: URL?

    @AppStorage("MAAUseCopilotList") var useCopilotList = false

    @Published var isCopilotListRunning = false

    @AppStorage("MAACopilotListConfig") private var serializedCopilotListConfig: String?

    @Published var copilotListConfig = CopilotListConfiguration()

    // MARK: - Recognition

    @Published var recruitConfig = RecruitConfiguration.recognition
    @Published var recruit: MAARecruit?
    @Published var depot: MAADepot?
    @Published var videoRecoginition: URL?
    @Published var operBox: MAAOperBox?

    // MARK: - Connection Settings

    @AppStorage("MAAConnectionAddress") var connectionAddress = "127.0.0.1:5555"

    @AppStorage("MAAConnectionProfile") var connectionProfile = "CompatMac"

    @AppStorage("MAAUseAdbLite") var useAdbLite = true

    @AppStorage("MAATouchMode") var touchMode = MaaTouchMode.maatouch {
        didSet {
            Task {
                if touchMode == .MacPlayTools {
                    useAdbLite = false
                    connectionProfile = "CompatMac"
                } else {
                    useAdbLite = true
                }

                try await loadResource(channel: clientChannel)
            }
        }
    }

    // MARK: - Game Settings

    @AppStorage("MAAClientChannel") var clientChannel = MAAClientChannel.default {
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

    // MARK: - Initializer

    init() {
        do {
            fileLogger = try FileLogger(
                url: Self.userDirectory.appendingPathComponent("debug", isDirectory: true)
                    .appendingPathComponent("gui.log", isDirectory: false))
        } catch {
            fileLogger = FileLogger()
            logError("日志文件出错: \(error.localizedDescription)")
        }

        loadUserCopilots()

        initCopilotListConfig()

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

        NotificationCenter.default
            .publisher(for: .MAAReceivedCallbackMessage)
            .receive(on: RunLoop.main)
            .sink(receiveValue: processMessage)
            .store(in: &cancellables)

        initScheduledDailyTaskTimer()
    }
}

// MARK: - MaaCore

extension MAAViewModel {
    func initialize() async throws {
        try await MAAProvider.shared.setUserDirectory(path: Self.userDirectory.path)
        try await loadResource(channel: clientChannel)
    }

    func ensureHandle(requireConnect: Bool = true) async throws {
        if handle == nil {
            handle = try MAAHandle(options: instanceOptions)
        }

        guard await handle?.running == false else {
            throw MAAError.handleNotRunning
        }

        logs.removeAll()
        taskIDMap.removeAll()
        taskStatus.removeAll()

        guard requireConnect else { return }

        logTrace("ConnectingToEmulator")
        if touchMode == .MacPlayTools {
            logTrace("如果长时间连接不上或出错，请尝试下载使用“文件” > “PlayCover链接…”中的最新版本")
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
    }

    func screenshot() async throws -> NSImage {
        guard let image = try await handle?.getImage() else {
            throw MAAError.imageUnavailable
        }

        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
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

    /// Load resources from bundled, user, and remote resources.
    ///
    /// Should be the outermost call to load resources.
    private func loadResource(channel: MAAClientChannel) async throws {
        // Initialize map data
        MapHelper.loadMapData()

        let (preferUser, currentResourceVersion) = try resourceChannel.version()
        try await loadResource(url: Bundle.main.resourceURL!, channel: channel)

        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        if preferUser {
            try await loadResource(url: documentsDirectory, channel: channel)
            try await loadResource(url: documentsDirectory.appendingPathComponent("cache"), channel: channel)
            logTrace(
                """
                外部资源版本：\(currentResourceVersion.activity.name)
                更新时间：\(currentResourceVersion.last_updated)
                """)
        } else {
            logTrace(
                """
                内置资源版本：\(currentResourceVersion.activity.name)
                更新时间：\(currentResourceVersion.last_updated)
                """)
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
            guard case var .startup(config) = task.task else {
                continue
            }

            config.client_type = channel
            if config.client_type == .default {
                config.start_game_enabled = false
            }

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
            .AdbLiteEnabled: useAdbLite ? "1" : "0",
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
            try await startTasks()
        } catch {
            logError("ConnectFailed")
            logInfo("CheckSettings")
        }
    }

    private func startTasks() async throws {
        status = .pending
        defer { handleEarlyReturn(backTo: .idle) }

        var firstStart = true
        for (index, task) in tasks.enumerated() {
            guard case var .startup(config) = task.task else {
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
            guard case var .closedown(config) = task.task else {
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

// MARK: - Copilot Management

extension MAAViewModel {
    func loadUserCopilots() {
        copilots.formUnion(externalDirectory.copilots)
        copilots.formUnion(recordingDirectory.copilots)
    }

    func addCopilots(_ providers: [NSItemProvider]) -> Bool {
        Task {
            for provider in providers {
                if let url = try? await provider.loadURL() {
                    let value = try? url.resourceValues(forKeys: [.contentTypeKey])
                    if value?.contentType == .json {
                        copilots.insert(url)
                    } else if value?.contentType?.conforms(to: .movie) == true {
                        try? await recognizeVideo(video: url)
                    }
                }
            }
            self.useCopilotList = false
            self.selectedCopilotURL = self.copilots.urls.last
        }
        return true
    }

    func addCopilots(_ results: Result<[URL], Error>) {
        if case let .success(urls) = results {
            copilots.formUnion(urls)
        }
    }

    func downloadCopilot(id: String?) {
        guard let id else { return }

        let file =
            externalDirectory
            .appendingPathComponent(id)
            .appendingPathExtension("json")

        let url = URL(string: "https://prts.maa.plus/copilot/get/\(id)")!
        Task {
            self.downloading = true
            do {
                let data = try await URLSession.shared.data(from: url).0
                let response = try JSONDecoder().decode(CopilotResponse.self, from: data)
                try response.data.content.write(toFile: file.path, atomically: true, encoding: .utf8)
                copilots.insert(file)
                logInfo("下载成功: \(file.lastPathComponent)")
                self.useCopilotList = false
                self.selectedCopilotURL = file
            } catch {
                print(error)
                logInfo("下载失败: \(error.localizedDescription)")
            }
            self.downloading = false
        }
    }

    func deleteCopilot(url: URL) {
        copilots.remove(url)

        copilotListConfig.items.removeAll(where: { $0.filename == url.path })

        guard canDeleteFile(url) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    func canDeleteFile(_ url: URL?) -> Bool {
        [externalDirectory, recordingDirectory]
            .compactMap { url?.path.starts(with: $0.path) }
            .first(where: { $0 })
            ?? false
    }

    var bundledDirectory: URL {
        Bundle.main.resourceURL!
            .appendingPathComponent("resource")
            .appendingPathComponent("copilot")
    }

    var externalDirectory: URL {
        let directory = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("copilot")

        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
        }

        return directory
    }

    var recordingDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("cache")
            .appendingPathComponent("CombatRecord")
    }
}

// MARK: Copilot List

extension MAAViewModel {
    func startCopilot() async throws {
        status = .pending
        defer { handleEarlyReturn(backTo: .idle) }

        if useCopilotList {
            try await ensureHandle()

            logTrace("开始添加任务到战斗列表")

            guard copilotListConfig.items.firstIndex(where: { $0.enabled }) != nil else {
                logTrace("没有启用的战斗列表任务")
                return
            }

            for (_, item) in copilotListConfig.items.enumerated() where item.enabled {

                let config = RegularCopilotConfiguration(
                    filename: item.filename,
                    formation: copilotListConfig.formation,
                    add_trust: copilotListConfig.add_trust,
                    is_raid: item.is_raid,
                    use_sanity_potion: copilotListConfig.use_sanity_potion,
                    need_navigate: item.need_navigate,
                    navigate_name: item.navigate_name
                )

                let copilot = CopilotConfiguration.regular(config)

                guard let params = copilot.params else {
                    continue
                }

                logTrace("添加关卡：\(item.navigate_name) \(item.is_raid ? "突袭" : "普通")")

                do {
                    _ = try await handle?.appendTask(type: .Copilot, params: params)
                } catch {
                    logError("添加关卡失败：\(error.localizedDescription)")
                    return
                }
            }

            isCopilotListRunning = true
            try await handle?.start()

        } else {
            guard let copilot,
                let params = copilot.params
            else {
                return
            }

            try await ensureHandle()

            switch copilot {
            case .regular:
                _ = try await handle?.appendTask(type: .Copilot, params: params)
            case .sss:
                _ = try await handle?.appendTask(type: .SSSCopilot, params: params)
            }

            try await handle?.start()
        }

        status = .busy
    }

    func addToCopilotList(copilot: MAACopilot, url: URL) {
        let name = copilot.doc?.title ?? url.lastPathComponent

        let stage_name = copilot.stage_name
        guard !stage_name.isEmpty else {
            logError("关卡名不能为空")
            return
        }

        guard let navigate_name = MapHelper.findMap(stage_name)?.code else {
            logError("找不到关卡 '\(stage_name)' 的地图数据，请更新资源")

            let alert = NSAlert()
            alert.messageText = "地图数据不存在"
            alert.informativeText = "找不到关卡 '\(stage_name)' 的地图数据，是否需要更新资源？"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "更新")
            alert.addButton(withTitle: "取消")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                showResourceUpdate = true
            }
            return
        }

        // is_raid: DifficultyFlags == .raid or .normal_raid
        // If DifficultyFlags is .normal_raid, add normal item first
        let is_raid =
            copilot.difficulty?.rawValue == DifficultyFlags.raid.rawValue
            || copilot.difficulty?.rawValue == DifficultyFlags.normal_raid.rawValue
        if copilot.difficulty?.rawValue == DifficultyFlags.normal_raid.rawValue {
            let item = CopilotItemConfiguration(
                enabled: true,
                filename: url.path,
                name: name,
                is_raid: false,
                need_navigate: true,
                navigate_name: navigate_name
            )
            copilotListConfig.items.append(item)
        }

        let item = CopilotItemConfiguration(
            enabled: true,
            filename: url.path,
            name: name,
            is_raid: is_raid,
            need_navigate: true,
            navigate_name: navigate_name,
        )
        copilotListConfig.items.append(item)
    }

    func removeFromCopilotList(at index: Int) {
        copilotListConfig.items.remove(at: index)
    }

    func moveCopilotItem(from source: Int, to destination: Int) {
        copilotListConfig.items.move(fromOffsets: IndexSet(integer: source), toOffset: destination)
    }

    func getCurrentCopilotStageName() -> String? {
        guard isCopilotListRunning else { return nil }
        return copilotListConfig.items.first(where: { $0.enabled }).map { item in
            "\(item.navigate_name) \(item.is_raid ? "突袭" : "普通")"
        }
    }

    private func initCopilotListConfig() {
        if let serializedString = serializedCopilotListConfig,
            let data = serializedString.data(using: .utf8),
            let config = try? JSONDecoder().decode(CopilotListConfiguration.self, from: data)
        {
            self.copilotListConfig = config
        } else {
            if serializedCopilotListConfig != nil {
                logError("Failed to decode CopilotListConfiguration from saved data.")
            }
        }

        $copilotListConfig
            .sink { [weak self] newConfig in
                guard let self else { return }

                do {
                    let data = try JSONEncoder().encode(newConfig)
                    if let jsonString = String(data: data, encoding: .utf8) {
                        if jsonString != self.serializedCopilotListConfig {
                            self.serializedCopilotListConfig = jsonString
                        }
                    } else {
                        logError("Failed to serialize CopilotListConfiguration to string.")
                    }
                } catch {
                    logError("Failed to encode CopilotListConfiguration: \(error.localizedDescription)")
                }
            }
            .store(in: &cancellables)
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

    func miniGame(name: String) async throws {
        status = .pending
        defer { handleEarlyReturn(backTo: .idle) }

        try await ensureHandle()

        let params = ["task_names": [name]]
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

    private func disableAwake() {
        guard let awakeAssertionID else { return }
        guard let wakeupAssertionID else { return }
        IOPMAssertionRelease(awakeAssertionID)
        IOPMAssertionRelease(wakeupAssertionID)
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

// MARK: - Value Extensions

extension URL {
    var copilots: [URL] {
        guard
            let urls = try? FileManager.default.contentsOfDirectory(
                at: self,
                includingPropertiesForKeys: [.contentTypeKey],
                options: .skipsHiddenFiles)
        else { return [] }

        return urls.filter { url in
            let value = try? url.resourceValues(forKeys: [.contentTypeKey])
            return value?.contentType == .json
        }
        .sorted { lhs, rhs in
            lhs.lastPathComponent < rhs.lastPathComponent
        }
    }
}

extension Set where Element == URL {
    var urls: [URL] { sorted { $0.lastPathComponent < $1.lastPathComponent } }
}

// MARK: - Download Model

private struct CopilotResponse: Codable {
    let data: CopilotData

    struct CopilotData: Codable {
        let content: String
    }
}

// MARK: - NSItemProvider Extension

extension NSItemProvider {
    @MainActor fileprivate func loadURL() async throws -> URL {
        let handle = ProgressActor()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let progress = loadObject(ofClass: URL.self) { object, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let object else {
                        continuation.resume(throwing: MAAError.emptyItemObject)
                        return
                    }

                    continuation.resume(returning: object)
                }

                Task {
                    await handle.bind(progress: progress)
                }
            }
        } onCancel: {
            Task {
                await handle.cancel()
            }
        }
    }
}

private actor ProgressActor {
    private var progress: Progress?
    private var cancelled = false

    func bind(progress: Progress) {
        guard !cancelled else { return }
        self.progress = progress
        progress.resume()
    }

    func cancel() {
        cancelled = true
        progress?.cancel()
    }
}
