//
//  MAAViewModel.swift
//  MAA
//
//  Created by hguandl on 13/4/2023.
//

import Combine
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

    private var handle: MAAHandle?

    // MARK: - Core Callback

    @Published var logs = [MAALog]()
    @Published var trackTail = false

    private var logObserver: Cancellable?

    // MARK: - Daily Tasks

    @Published var tasks: OrderedStore<MAATask>
    @Published var taskIDMap: [Int32: UUID] = [:]
    @Published var newTaskAdded = false
    private var taskObserver: Cancellable?

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

    // MARK: - Connection Settings

    @AppStorage("MAAConnectionAddress") var connectionAddress = "127.0.0.1:5555"

    @AppStorage("MAAConnectionProfile") var connectionProfile = "CompatMac"

    @AppStorage("MAAUseAdbLite") var useAdbLite = true

    @AppStorage("MAATouchMode") var touchMode = MaaTouchMode.maatouch

    // MARK: - Initializer

    init() {
        do {
            let data = try Data(contentsOf: tasksURL)
            tasks = try PropertyListDecoder().decode(OrderedStore<MAATask>.self, from: data)
        } catch {
            tasks = .init(MAATask.defaults)
        }

        taskObserver = $tasks.sink(receiveValue: writeBack)

        logObserver = NotificationCenter.default
            .publisher(for: .MAAReceivedCallbackMessage)
            .receive(on: RunLoop.main)
            .sink(receiveValue: processMessage)
    }
}

// MARK: - MaaCore

extension MAAViewModel {
    func initialize() async throws {
        try await MAAProvider.shared.setUserDirectory(path: userDirectory.path)
        try await MAAProvider.shared.loadResource(path: Bundle.main.resourcePath!)
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
        try await handle?.connect(adbPath: adbPath, address: connectionAddress, profile: connectionProfile)
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

        try await ensureHandle()

        for (id, task) in tasks.items {
            guard let params = task.params else { continue }

            if case let .startup(config) = task, config.client_type.isGlobal {
                let extraResource = userDirectory
                    .appendingPathComponent("resource")
                    .appendingPathComponent("global")
                    .appendingPathComponent(config.client_type.rawValue)
                try await MAAProvider.shared.loadResource(path: extraResource.path)
            }

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

// MARK: Recognition

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
