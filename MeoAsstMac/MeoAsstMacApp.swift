//
//  MeoAsstMacApp.swift
//  MeoAsstMac
//
//  Created by hguandl on 8/10/2022.
//

import Combine
import SwiftUI

@main
struct MeoAsstMacApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem, addition: {})
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    // MARK: App states

    enum MaaStatus: Equatable {
        case pending
        case value(Bool)
    }

    @Published var appLogs: [String] = []
    @Published var extractingResource = false
    @Published var maaRunning = MaaStatus.value(false)
    @Published var maaVersion: String?

    private var logObserver: AnyCancellable?
    private var maaObserver: AnyCancellable?

    // MARK: General settings

    @AppStorage("MAAEnabledTasks") var tasks = MaaTask.defaults

    // MARK: Fight settings

    /// - Tag: 吃理智药
    @AppStorage("MAAFightUseSanityPotion") var useSanityPotion = false
    @AppStorage("MAAFightSanityPotionAmount") var sanityPotion = 999

    /// - Tag: 吃源石
    @Published var useOriginitePrime = false
    @Published var originitePrime = 0

    /// - Tag: 指定次数
    @Published var limitPerformBattles = false
    @Published var performBattles = 5

    /// - Tag: 关卡选择
    @AppStorage("MAAFightStageSelect") var stageSelect = ""

    /// - Tag: 剩余理智
    @AppStorage("MAAFightRemainingSanityStage") var remainingSanityStage = ""

    // MARK: Recruit settings

    /// - Tag: 自动刷新 3 星 Tags
    @AppStorage("MAARecruitAutoRefresh") var autoRefresh = true

    /// - Tag: 自动使用加急许可
    @Published var autoUseExpedited = false

    /// - Tag: 3 星设置 7:40 而非 9:00
    @AppStorage("MAARecruitLevel3UseShortTime") var level3UseShortTime = false

    /// - Tag: 每次执行时最大招募次数
    @AppStorage("MAARecruitMaxTimes") var recruitMaxTimes = 4

    /// - Tag: 手动确认“支援机械”
    @AppStorage("MAARecruitManuallySelectLevel1") var manuallySelectLevel1 = true

    /// - Tag: 自动确认 3 星
    @AppStorage("MAARecruitAutoSelectLevel3") var autoSelectLevel3 = true

    /// - Tag: 自动确认 4 星
    @AppStorage("MAARecruitAutoSelectLevel4") var autoSelectLevel4 = true

    /// - Tag: 自动确认 5 星
    @AppStorage("MAARecruitAutoSelectLevel5") var autoSelectLevel5 = false

    // MARK: Infrast settings

    @AppStorage("MAAInfrastMode") var infrastMode = 0

    @AppStorage("MAAInfrastFacilities") var facilities = MaaInfrastFacility.defaults

    /// - Tag: 无人机用途
    @AppStorage("MAAInfrastDroneUsage") var droneUsage = DroneUsage.Money

    /// - Tag: 基建工作心情阈值
    @AppStorage("MAAInfrastDormThreshold") var dormThreshold = 0.3

    /// - Tag: 宿舍空余位置蹭信赖
    @AppStorage("MAAInfrastDormTrust") var dormTrust = true

    /// - Tag: 不将已进驻的干员放入宿舍
    @AppStorage("MAAInfrastDormFilterNotStationed") var dormFilterStationed = false

    /// - Tag: 源石碎片自动补货
    @AppStorage("MAAInfrastOriginiumReplenishment") var originiumReplenishment = true

    // MARK: Mall settings

    /// - Tag: 信用购物
    @AppStorage("MAAMallSocialPtShop") var socialPtShop = true

    /// - Tag: 优先购买 子串即可 分号分隔
    @AppStorage("MaaMallHighPriority") var highPriority = "招聘许可;龙门币"

    /// - Tag: 黑名单 子串即可 分号分隔
    @AppStorage("MaaMallBlacklist") var blacklist = "碳;家具"

    /// - Tag: 信用溢出时无视黑名单
    @AppStorage("MAAMallForceShoppingIfCreditFull") var forceShoppingIfCreditFull = false

    // MARK: Roguelike settings

    @AppStorage("MAARougelikeTheme") var rougelikeTheme = "Phantom"

    @AppStorage("MAARoguelikeMode") var roguelikeMode = 0

    @AppStorage("MAARoguelikeTimesLimit") var roguelikeTimesLimit = 9999999

    @AppStorage("MAARoguelikeGoldEnabled") var roguelikeGoldEnabled = true

    @AppStorage("MAARoguelikeGoldLimit") var roguelikeGoldLimit = 999

    @AppStorage("MAARoguelikeStopWhenGoldLimit") var roguelikeStopWhenGoldLimit = true

    @AppStorage("MAARoguelikeStartingSquad") var roguelikeStartingSquad = "指挥分队"

    @AppStorage("MAARoguelikeStartingRoles") var roguelikeStartingRoles = "取长补短"

    @AppStorage("MAARoguelikeStartingCoreChar") var roguelikeCoreChar = ""

    // MARK: Connection settings

    @AppStorage("MAAConnectionAddress") var connectionAddress = "127.0.0.1:5555"

    @AppStorage("MAAConnectionProfile") var connectionProfile = "CompatMac"

    @AppStorage("MAATouchMode") var touchMode = MaaTouchMode.maatouch

    // MARK: Startup settings

    @AppStorage("MAAClientChannel") var clientChannel = MaaClientChannel.default

    // MARK: Maa controller

    nonisolated func applicationWillFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            NSWindow.allowsAutomaticWindowTabbing = false
        }
    }

    nonisolated func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private(set) var handle: Maa?

    func initializeMaa() async {
        /// - Tag: MaaCallbackMesage
        logObserver = NotificationCenter.default
            .publisher(for: .MAAReceivedCallbackMessage)
            .receive(on: RunLoop.main)
            .sink { output in
                if let msg = output.object as? MaaMessage {
                    let logTime = dateFormatter.string(from: Date())
                    self.appLogs.append("\(logTime) \(msg.description)")
                }
            }

        guard await Maa.setUserDirectory(path: appDataURL.path) else {
            appLogs.append("目录设置失败")
            return
        }
        appLogs.append("目录设置成功")

        guard await Maa.loadResource(path: Bundle.main.resourcePath!) else {
            appLogs.append("资源读取失败")
            return
        }

        if clientChannel.isGlobal {
            let extraDataURL = resourceURL
                .appendingPathComponent("global")
                .appendingPathComponent(clientChannel.rawValue)
            guard await Maa.loadResource(path: extraDataURL.path) else {
                appLogs.append("资源读取失败")
                return
            }
            appLogs.append("\(clientChannel) 资源读取成功")
        }

        appLogs.append("资源读取成功")
    }

    func setupMaa() async -> Bool {
        let options = [
            MaaInstanceOptionKey.TouchMode: touchMode.rawValue
        ]
        handle = await Maa(options: options)
        guard await connectAVD() else { return false }
        guard await setupTasks() else { return false }
        return true
    }

    func startMaa() async -> Bool {
        maaObserver = Timer.publish(every: 1.0, on: RunLoop.main, in: .common)
            .autoconnect()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task {
                    let running = await self?.handle?.running
                    self?.maaRunning = .value(running ?? false)
                }
            }
        return await handle?.start() ?? false
    }

    func stopMaa() async -> Bool {
        await handle?.stop() ?? false
    }

    func cleanupMaa() async {
        await handle?.destroy()
    }

    private func connectAVD() async -> Bool {
        await handle?.connect(adbPath: Bundle.main.url(forAuxiliaryExecutable: "adb")!.path, address: connectionAddress, profile: connectionProfile) ?? false
    }

    private func setupTasks() async -> Bool {
        guard let handle = handle else { return false }

        let runners = tasks
            .filter { $0.enabled }
            .map { task in
                let taskType = task.key.rawValue
                let taskParams = taskParams(for: task)
                return Task {
                    await handle.appendTask(taskType: taskType, taskConfig: taskParams)
                }
            }

        for runner in runners {
            if await runner.value <= 0 {
                return false
            }
        }

        return true
    }

    // MARK: Maa configuration

    private func taskParams(for task: MaaTask) -> String {
        let configuration = taskConfiguration(for: task)
        let data = try! JSONEncoder().encode(configuration)
        return String(data: data, encoding: .utf8)!
    }

    private func taskConfiguration(for task: MaaTask) -> any MaaTaskConfiguration {
        switch task.key {
        case .StartUp:
            if clientChannel != .default {
                return StartupConfiguration(client_type: clientChannel.rawValue, start_game_enabled: true)
            } else {
                return StartupConfiguration(client_type: "", start_game_enabled: false)
            }
        case .Recruit:
            let select = [4, 5]
            let confirm = {
                var confirm = [Int]()
                if autoSelectLevel3 { confirm.append(3) }
                if autoSelectLevel4 { confirm.append(4) }
                if autoSelectLevel5 { confirm.append(5) }
                return confirm
            }()
            let recruitmentTime = {
                var recruitmentTime = ["3": 540, "4": 540, "5": 540, "6": 540]
                if level3UseShortTime {
                    recruitmentTime["3"] = 460
                }
                return recruitmentTime
            }()
            return RecruitConfiguration(refresh: autoRefresh,
                                        select: select,
                                        confirm: confirm,
                                        times: recruitMaxTimes,
                                        expedite: autoUseExpedited,
                                        skip_robot: manuallySelectLevel1,
                                        recruitment_time: recruitmentTime)
        case .Infrast:
            return InfrastConfiguration(mode: infrastMode,
                                        facility: facilities.map(\.name.rawValue),
                                        drones: droneUsage.rawValue,
                                        threshold: Float(dormThreshold),
                                        replenish: originiumReplenishment,
                                        dorm_notstationed_enabled: dormFilterStationed,
                                        dorm_trust_enabled: dormTrust)
        case .Fight:
            return FightConfiguration(stage: stageSelect,
                                      medicine: useSanityPotion ? sanityPotion : nil,
                                      stone: useOriginitePrime ? originitePrime : nil,
                                      times: limitPerformBattles ? performBattles : nil)
        case .Visit:
            return VisitConfiguration()
        case .Mall:
            let buyFirst = highPriority.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            let buyBlacklist = blacklist.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            return MallConfiguration(shopping: socialPtShop,
                                     buy_first: buyFirst,
                                     blacklist: buyBlacklist,
                                     force_shopping_if_credit_full: forceShoppingIfCreditFull)
        case .Award:
            return AwardConfiguration()
        case .Roguelike:
            return RoguelikeConfiguration(theme: rougelikeTheme,
                                          mode: roguelikeMode,
                                          starts_count: roguelikeTimesLimit,
                                          investments_count: roguelikeGoldLimit,
                                          stop_when_investment_full: roguelikeStopWhenGoldLimit,
                                          squad: roguelikeStartingSquad,
                                          roles: roguelikeStartingRoles,
                                          core_char: roguelikeCoreChar)
        }
    }

    // MARK: Copilot

    func startCopilotTask(for url: URL, formation: Bool, sss: Bool, times: Int) async -> Bool {
        if handle == nil {
            let options = [
                MaaInstanceOptionKey.TouchMode: touchMode.rawValue
            ]
            handle = await Maa(options: options)
        }
        guard let handle, await !handle.running else { return false }
        let config = CopilotConfiguration(filename: url.path, formation: formation)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let configData = try! encoder.encode(config)
        let configString = String(data: configData, encoding: .utf8)!
        let taskType = sss ? "SSSCopilot" : "Copilot"
        for _ in 0 ..< times {
            _ = await handle.appendTask(taskType: taskType, taskConfig: configString)
        }
        guard await connectAVD() else { return false }
        return await startMaa()
    }

    // MARK: Resource loader

    lazy var resourceURL = Bundle.main.resourceURL!.appendingPathComponent("resource")
    lazy var appDataURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    lazy var asstLogURL = appDataURL.appendingPathComponent("debug").appendingPathComponent("asst.log")
}

// MARK: Task configurations

private protocol MaaTaskConfiguration: Encodable {}

private struct StartupConfiguration: MaaTaskConfiguration {
    let client_type: String
    let start_game_enabled: Bool
}

private struct FightConfiguration: MaaTaskConfiguration {
    let stage: String
    let medicine: Int?
    let stone: Int?
    let times: Int?
}

private struct RecruitConfiguration: MaaTaskConfiguration {
    let refresh: Bool
    let select: [Int]
    let confirm: [Int]
    let times: Int
    let expedite: Bool
    let skip_robot: Bool
    let recruitment_time: [String: Int]
}

private struct InfrastConfiguration: MaaTaskConfiguration {
    let mode: Int
    let facility: [String]
    let drones: String
    let threshold: Float
    let replenish: Bool
    let dorm_notstationed_enabled: Bool
    let dorm_trust_enabled: Bool
}

private struct VisitConfiguration: MaaTaskConfiguration {}

private struct MallConfiguration: MaaTaskConfiguration {
    let shopping: Bool
    let buy_first: [String]
    let blacklist: [String]
    let force_shopping_if_credit_full: Bool
}

private struct AwardConfiguration: MaaTaskConfiguration {}

private struct RoguelikeConfiguration: MaaTaskConfiguration {
    let theme: String
    let mode: Int
    let starts_count: Int
    let investments_count: Int
    let stop_when_investment_full: Bool
    let squad: String
    let roles: String
    let core_char: String
}

private struct CopilotConfiguration: MaaTaskConfiguration {
    let filename: String
    let formation: Bool
}

// MARK: Date formatter

private let dateFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateFormat = "MM-dd HH:mm:ss"
    return df
}()
