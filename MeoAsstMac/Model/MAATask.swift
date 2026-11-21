//
//  MAATask.swift
//  MAA
//
//  Created by hguandl on 15/4/2023.
//

import SwiftUI

enum MAATask: Codable, Equatable {
    case startup(StartupConfiguration)
    case closedown(ClosedownConfiguration)
    case recruit(RecruitConfiguration)
    case infrast(InfrastConfiguration)
    case fight(FightConfiguration)
    case mall(MallConfiguration)
    case award(AwardConfiguration)
    case switchTheme(SwitchThemeConfiguration)
    case roguelike(RoguelikeConfiguration)
    case reclamation(ReclamationConfiguration)
}

let defaultTaskConfigurations: [any MAATaskConfiguration] = [
    StartupConfiguration(),
    RecruitConfiguration(),
    InfrastConfiguration(),
    FightConfiguration(),
    MallConfiguration(),
    AwardConfiguration(),
    SwitchThemeConfiguration(),
    RoguelikeConfiguration(),
    ReclamationConfiguration(),
    ClosedownConfiguration(),
]

extension MAATaskType: Codable, CustomStringConvertible {
    var description: String {
        switch self {
        case .StartUp:
            return String(localized: "开始唤醒")
        case .CloseDown:
            return String(localized: "关闭游戏")
        case .Recruit:
            return String(localized: "自动公招")
        case .Infrast:
            return String(localized: "基建换班")
        case .Fight:
            return String(localized: "刷理智")
        case .Mall:
            return String(localized: "收取信用及购物")
        case .Award:
            return String(localized: "领取奖励")
        case .SwitchTheme:
            return String(localized: "更换主题")
        case .Roguelike:
            return String(localized: "自动肉鸽")
        case .Copilot:
            return String(localized: "自动抄作业")
        case .SSSCopilot:
            return String(localized: "自动抄保全作业")
        case .ParadoxCopilot:
            return String(localized: "自动抄悖论模拟作业")
        case .Depot:
            return String(localized: "仓库识别")
        case .Reclamation:
            return String(localized: "生息演算")
        case .VideoRecognition:
            return String(localized: "视频识别")
        case .OperBox:
            return String(localized: "干员识别")
        case .Custom:
            return String(localized: "自定义")
        }
    }
}

// MARK: Task Persistance

struct DailyTask: Codable, Equatable, Identifiable {
    let id: UUID
    let task: MAATask
    var enabled: Bool
}

struct ClientTaskBatch: Codable {
    let client: MAAClientChannel
    var tasks: [DailyTask]
    var followedByAnotherClient = false

    static func batches(for tasks: [DailyTask], defaultClient: MAAClientChannel) -> [Self] {
        var batches = [Self]()
        var client = defaultClient
        for entry in tasks where entry.enabled {
            var task = entry.task
            switch task {
            case .startup(var config):
                let next = config.clientOverride ?? defaultClient
                config.start_game_enabled = config.launchesClient || next != client
                client = next
                config.client_type = client
                config.clientOverride = nil
                task = .startup(config)
            case .closedown(var config):
                config.client_type = client
                task = .closedown(config)
            case .fight(var config):
                config.client_type = client.rawValue
                config.server = client.reportServer
                task = .fight(config)
            case .recruit(var config):
                config.server = client.reportServer
                task = .recruit(config)
            default:
                break
            }
            if batches.last?.client != client {
                if !batches.isEmpty { batches[batches.count - 1].followedByAnotherClient = true }
                batches.append(Self(client: client, tasks: []))
            }
            batches[batches.count - 1].tasks.append(.init(id: entry.id, task: task, enabled: true))
        }
        return batches
    }
}

extension DailyTask {
    init<T: MAATaskConfiguration>(config: T) {
        switch config.type {
        case .Roguelike, .Reclamation:
            self.init(id: UUID(), task: config.projectedTask, enabled: false)
        default:
            self.init(id: UUID(), task: config.projectedTask, enabled: true)
        }
    }
}

extension Array where Element == DailyTask {
    func client(before id: UUID, defaultClient: MAAClientChannel) -> MAAClientChannel {
        for entry in prefix(while: { $0.id != id }).reversed() where entry.enabled {
            if case .startup(let config) = entry.task { return config.clientOverride ?? defaultClient }
        }
        return defaultClient
    }

    subscript(_ id: UUID) -> MAATask? {
        get {
            first { $0.id == id }?.task
        }
        set {
            if let newValue, let index = firstIndex(id: id) {
                self[index] = .init(id: id, task: newValue, enabled: self[index].enabled)
            }
        }
    }

    func firstIndex(id: UUID) -> Int? {
        firstIndex { $0.id == id }
    }

    mutating func append<T: MAATaskConfiguration>(config: T) {
        append(.init(config: config))
    }

    mutating func remove(id: UUID) {
        removeAll { $0.id == id }
    }
}

extension MAAViewModel {
    func writeBack(_ newValue: [DailyTask]) {
        let data = try? PropertyListEncoder().encode(newValue)
        try? data?.write(to: tasksURL)
    }
}
