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
    @Published var downloadCopilot: String?
    @Published var showImportCopilot = false
    @Published var copilotDetailMode: CopilotDetailMode = .log

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

        do {
            let data = try Data(contentsOf: tasksURL)
            tasks = try PropertyListDecoder().decode([DailyTask].self, from: data)
            print("Read from \(tasksURL.path)")
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
                print("Migrated")
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
    }

    func screenshot() async throws -> NSImage {
        guard let image = try await handle?.getImage() else {
            throw MAAError.imageUnavailable
        }

        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    private func resourceVersion(of url: URL) throws -> MAAResourceVersion {
        let versionURL = url.appendingPathComponent("resource").appendingPathComponent("version.json")
        let data = try Data(contentsOf: versionURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(MAAResourceVersion.self, from: data)
    }

    private func loadResource(url: URL, channel: MAAClientChannel) async throws {
        try await MAAProvider.shared.loadResource(path: url.path)

        if channel.isGlobal {
            let extraResource = url.appendingPathComponent("resource")
                .appendingPathComponent("global")
                .appendingPathComponent(channel.rawValue)
            if FileManager.default.fileExists(atPath: extraResource.path) {
                try await MAAProvider.shared.loadResource(path: extraResource.path)
            }
        }

        if touchMode == .MacPlayTools {
            let platformResource = url.appendingPathComponent("resource")
                .appendingPathComponent("platform_diff")
                .appendingPathComponent("iOS")
            if FileManager.default.fileExists(atPath: platformResource.path) {
                try await MAAProvider.shared.loadResource(path: platformResource.path)
            }
        }
    }

    private func loadResource(channel: MAAClientChannel) async throws {
        let bundledResourceVersion = try resourceVersion(of: Bundle.main.resourceURL!)
        try await loadResource(url: Bundle.main.resourceURL!, channel: channel)
        logTrace(
            """
            内置资源版本：\(bundledResourceVersion.activity.name)
            更新时间：\(bundledResourceVersion.last_updated)
            """)

        let currentResourceVersion: MAAResourceVersion
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        if let userResourceVersion = try? resourceVersion(of: documentsDirectory) {
            if userResourceVersion.last_updated > bundledResourceVersion.last_updated {
                try await loadResource(url: documentsDirectory, channel: channel)
                try await loadResource(url: documentsDirectory.appendingPathComponent("cache"), channel: channel)
                currentResourceVersion = userResourceVersion
                logTrace(
                    """
                    外部资源版本：\(userResourceVersion.activity.name)
                    更新时间：\(userResourceVersion.last_updated)
                    """)
            } else {
                currentResourceVersion = bundledResourceVersion
                logInfo("无需使用外部更新资源")
            }
        } else {
            currentResourceVersion = bundledResourceVersion
            logInfo("未找到外部更新资源")
        }

        Task.detached {
            let resmoteResourceVersionURL = URL(
                string: "https://github.com/MaaAssistantArknights/MaaResource/raw/refs/heads/main/resource/version.json"
            )!

            do {
                let (data, _) = try await URLSession.shared.data(from: resmoteResourceVersionURL)

                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .secondsSince1970
                let remoteResourceVersion = try decoder.decode(MAAResourceVersion.self, from: data)

                if remoteResourceVersion.last_updated > currentResourceVersion.last_updated {
                    await self.logInfo("发现新资源版本：\(remoteResourceVersion.last_updated)")
                } else {
                    await self.logInfo("资源已是最新版本")
                }
            } catch {
                await self.logError("无法检查资源更新: \(error.localizedDescription)")
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

        for (index, task) in tasks.enumerated() {
            guard case var .startup(config) = task.task else {
                continue
            }

            config.client_type = clientChannel
            tasks[index] = .init(id: task.id, task: .startup(config), enabled: task.enabled)

            if touchMode == .MacPlayTools, task.enabled, config.start_game_enabled {
                guard await startGame(client: config.client_type) else {
                    throw MAAError.gameStartFailed
                }
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

// MARK: Copilot

extension MAAViewModel {
    func startCopilot() async throws {
        status = .pending
        defer { handleEarlyReturn(backTo: .idle) }

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
