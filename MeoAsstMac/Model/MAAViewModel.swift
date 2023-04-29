//
//  MAAViewModel.swift
//  MAA
//
//  Created by hguandl on 13/4/2023.
//

import Combine
import IOKit.pwr_mgt
import Network
import SwiftUI

@MainActor class MAAViewModel: ObservableObject {
    // MARK: - Core Status

    enum Status: Equatable {
        case busy
        case idle
        case pending
    }

    @Published var status = Status.idle
    @Published var showLog = false

    private var awakeAssertionID: UInt32?
    private var handle: MAAHandle?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Core Callback

    @Published var logs = [MAALog]()
    @Published var trackTail = false

    // MARK: - Daily Tasks

    @Published var tasks: OrderedStore<MAATask>
    @Published var taskIDMap: [Int32: UUID] = [:]
    @Published var newTaskAdded = false

    enum TaskStatus: Equatable {
        case cancel
        case failure
        case running
        case success
    }

    @Published var taskStatus: [UUID: TaskStatus] = [:]

    let tasksURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first!
        .appendingPathComponent("UserTasks")
        .appendingPathExtension("plist")

    // MARK: - Copilot

    @Published var copilot: CopilotConfiguration?
    @Published var downloadCopilot: String?
    @Published var showImportCopilot = false

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

    @AppStorage("MAATouchMode") var touchMode = MaaTouchMode.maatouch

    // MARK: - Game Settings

    @AppStorage("MAAClientChannel") var clientChannel = MAAClientChannel.default {
        didSet {
            updateChannel(channel: clientChannel)
        }
    }

    // MARK: - Initializer

    init() {
        do {
            let data = try Data(contentsOf: tasksURL)
            tasks = try PropertyListDecoder().decode(OrderedStore<MAATask>.self, from: data)
        } catch {
            tasks = .init(MAATask.defaults)
        }

        $tasks.sink(receiveValue: writeBack).store(in: &cancellables)
        $status.sink(receiveValue: switchAwakeGuard).store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: .MAAReceivedCallbackMessage)
            .receive(on: RunLoop.main)
            .sink(receiveValue: processMessage)
            .store(in: &cancellables)
    }
}

// MARK: - MaaCore

extension MAAViewModel {
    func initialize() async throws {
        try await MAAProvider.shared.setUserDirectory(path: userDirectory.path)
        try await loadResource(channel: clientChannel)
    }

    func ensureHandle() async throws {
        if handle == nil {
            handle = try MAAHandle(options: instanceOptions)
        }

        guard await handle?.running == false else {
            throw NSError()
        }

        logs.removeAll()
        taskIDMap.removeAll()
        taskStatus.removeAll()

        logTrace("ConnectingToEmulator")
        if touchMode == .MacPlayTools {
            logTrace(["如果长时间连接不上或出错，请尝试下载使用", "“文件” > “PlayCover链接…” 中的最新版本"])
        }
        try await handle?.connect(adbPath: adbPath, address: connectionAddress, profile: connectionProfile)
        logTrace("Running")
    }

    func stop() async throws {
        status = .pending
        defer {
            if status == .pending {
                status = .busy
            }
        }

        try await handle?.stop()
        status = .idle
    }

    func screenshot() async throws -> NSImage {
        guard let image = try await handle?.getImage() else {
            throw NSError()
        }

        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    private func loadResource(channel: MAAClientChannel) async throws {
        try await MAAProvider.shared.loadResource(path: Bundle.main.resourcePath!)

        if channel.isGlobal {
            let extraResource = Bundle.main.resourceURL!
                .appendingPathComponent("resource")
                .appendingPathComponent("global")
                .appendingPathComponent(channel.rawValue)
            try await MAAProvider.shared.loadResource(path: extraResource.path)
        }
    }

    private func updateChannel(channel: MAAClientChannel) {
        for (id, task) in tasks.items {
            guard case var .startup(config) = task else {
                continue
            }

            config.client_type = channel
            if config.client_type == .default {
                config.start_game_enabled = false
            }

            tasks[id] = .startup(config)
        }

        Task {
            try await loadResource(channel: channel)
        }
    }

    private var userDirectory: URL {
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
    func startTasks() async throws {
        status = .pending
        defer {
            if status == .pending {
                status = .idle
            }
        }

        for (_, task) in tasks.items {
            guard case let .startup(config) = task else {
                continue
            }

            if touchMode == .MacPlayTools, config.enable, config.start_game_enabled {
                guard await startGame(client: config.client_type) else {
                    throw NSError()
                }
            }
        }

        try await ensureHandle()

        for (id, task) in tasks.items {
            guard let params = task.params else { continue }

            if let coreID = try await handle?.appendTask(type: task.typeName, params: params) {
                taskIDMap[coreID] = id
            }
        }

        try await handle?.start()

        status = .busy
    }
}

// MARK: Copilot

extension MAAViewModel {
    func startCopilot() async throws {
        status = .pending
        defer {
            if status == .pending {
                status = .idle
            }
        }

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
        defer {
            if status == .pending {
                status = .idle
            }
        }

        guard let params = MAATask.recruit(recruitConfig).params else {
            return
        }

        try await ensureHandle()
        try await _ = handle?.appendTask(type: .Recruit, params: params)
        try await handle?.start()

        status = .busy
    }

    func recognizeDepot() async throws {
        status = .pending
        defer {
            if status == .pending {
                status = .idle
            }
        }

        try await ensureHandle()
        try await _ = handle?.appendTask(type: .Depot, params: "")
        try await handle?.start()

        status = .busy
    }

    func recognizeVideo(video url: URL) async throws {
        status = .pending
        defer {
            if status == .pending {
                status = .idle
            }
        }

        let config = VideoRecognitionConfiguration(filename: url.path)
        guard let params = config.params else {
            return
        }

        try await ensureHandle()
        try await _ = handle?.appendTask(type: .VideoRecognition, params: params)
        try await handle?.start()

        status = .busy
    }

    func recognizeOperBox() async throws {
        status = .pending
        defer {
            if status == .pending {
                status = .idle
            }
        }

        try await ensureHandle()
        try await _ = handle?.appendTask(type: .OperBox, params: "")
        try await handle?.start()

        status = .busy
    }

    func gachaPoll(once: Bool) async throws {
        status = .pending
        defer {
            if status == .pending {
                status = .idle
            }
        }

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

// MARK: Task Configuration

extension MAAViewModel {
    func taskConfig<T: MAATaskConfiguration>(id: UUID) -> Binding<T> {
        Binding {
            self.tasks[id]?.unwrapConfig() ?? .init()
        } set: {
            self.tasks[id] = .init(config: $0)
        }
    }

    @ViewBuilder func taskConfigView(id: UUID) -> some View {
        switch tasks[id] {
        case .startup:
            StartupSettingsView(id: id)
        case .recruit:
            RecruitSettingsView(id: id)
        case .infrast:
            InfrastSettingsView(id: id)
        case .fight:
            FightSettingsView(id: id)
        case .mall:
            MallSettingsView(id: id)
        case .award:
            Text("此任务无自定义选项")
        case .roguelike:
            RoguelikeSettingsView(id: id)
        case .reclamation:
            ReclamationSettingsView(id: id)
        case .none:
            EmptyView()
        }
    }
}

// MARK: - Prevent Sleep

extension MAAViewModel {
    func switchAwakeGuard(_ newValue: Status) {
        switch newValue {
        case .busy, .pending:
            enableAwake()
        case .idle:
            disableAwake()
        }
    }

    private func enableAwake() {
        guard awakeAssertionID == nil else { return }
        var assertionID: UInt32 = 0
        let name = "MAA is running; sleep is diabled."
        let properties = [kIOPMAssertionTypeKey: kIOPMAssertionTypeNoDisplaySleep as CFString,
                          kIOPMAssertionNameKey: name as CFString,
                          kIOPMAssertionLevelKey: UInt32(kIOPMAssertionLevelOn)] as [String: Any]
        let result = IOPMAssertionCreateWithProperties(properties as CFDictionary, &assertionID)
        if result == kIOReturnSuccess {
            awakeAssertionID = assertionID
        }
    }

    private func disableAwake() {
        guard let awakeAssertionID else { return }
        IOPMAssertionRelease(awakeAssertionID)
        self.awakeAssertionID = nil
    }
}

// MARK: - MAAHelper XPC

extension MAAViewModel {
    func startGame(client: MAAClientChannel) async -> Bool {
        let connectionToService = NSXPCConnection(serviceName: "com.hguandl.MAAHelper")
        connectionToService.remoteObjectInterface = NSXPCInterface(with: MAAHelperProtocol.self)
        connectionToService.resume()

        defer { connectionToService.invalidate() }

        if let proxy = connectionToService.remoteObjectProxy as? MAAHelperProtocol {
            let result = await withCheckedContinuation { continuation in
                proxy.startGame(bundleName: client.appBundleName) { success in
                    continuation.resume(returning: success)
                }
            }

            if !result {
                return false
            } else {
                return await waitForEndpoint(address: connectionAddress)
            }
        }

        return false
    }
}

// MARK: - TCP Port Watcher

private func waitForEndpoint(address: String) async -> Bool {
    let parts = address.split(separator: ":")
    guard parts.count >= 2,
          let portNumber = UInt16(parts[1]),
          let port = NWEndpoint.Port(rawValue: portNumber)
    else {
        return false
    }
    let host = NWEndpoint.Host(String(parts[0]))
    let connection = NWConnection(host: host, port: port, using: .tcp)
    connection.start(queue: .global(qos: .background))

    for await online in connection.onlinePolls {
        if online { break }
        try? await Task.sleep(nanoseconds: 500_000_000)
        connection.restart()
    }

    return true
}

private extension NWConnection {
    var onlinePolls: AsyncStream<Bool> {
        AsyncStream { continuation in
            self.stateUpdateHandler = { state in
                switch state {
                case .setup, .preparing, .cancelled:
                    break
                case .waiting, .failed:
                    continuation.yield(false)
                case .ready:
                    continuation.yield(true)
                @unknown default:
                    fatalError()
                }
            }

            continuation.onTermination = { @Sendable _ in
                self.cancel()
            }
        }
    }
}
