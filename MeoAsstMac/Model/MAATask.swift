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
    case roguelike(RoguelikeConfiguration)
    case reclamation(ReclamationConfiguration)
}

extension MAATask {
    var configuration: any MAATaskConfiguration {
        switch self {
        case .startup(let config): config
        case .closedown(let config): config
        case .recruit(let config): config
        case .infrast(let config): config
        case .fight(let config): config
        case .mall(let config): config
        case .award(let config): config
        case .roguelike(let config): config
        case .reclamation(let config): config
        }
    }
}

let defaultTaskConfigurations: [any MAATaskConfiguration] = [
    StartupConfiguration(),
    RecruitConfiguration(),
    InfrastConfiguration(),
    FightConfiguration(),
    MallConfiguration(),
    AwardConfiguration(),
    RoguelikeConfiguration(),
    ReclamationConfiguration(),
    ClosedownConfiguration(),
]

extension MAATaskType: Codable, CustomStringConvertible {
    var description: String {
        switch self {
        case .StartUp:
            return NSLocalizedString("开始唤醒", comment: "")
        case .CloseDown:
            return NSLocalizedString("关闭游戏", comment: "")
        case .Recruit:
            return NSLocalizedString("自动公招", comment: "")
        case .Infrast:
            return NSLocalizedString("基建换班", comment: "")
        case .Fight:
            return NSLocalizedString("刷理智", comment: "")
        case .Mall:
            return NSLocalizedString("收取信用及购物", comment: "")
        case .Award:
            return NSLocalizedString("领取奖励", comment: "")
        case .Roguelike:
            return NSLocalizedString("自动肉鸽", comment: "")
        case .Copilot:
            return NSLocalizedString("自动抄作业", comment: "")
        case .SSSCopilot:
            return NSLocalizedString("自动抄保全作业", comment: "")
        case .Depot:
            return NSLocalizedString("仓库识别", comment: "")
        case .Reclamation:
            return NSLocalizedString("生息演算", comment: "")
        case .VideoRecognition:
            return NSLocalizedString("视频识别", comment: "")
        case .OperBox:
            return NSLocalizedString("干员识别", comment: "")
        case .Custom:
            return NSLocalizedString("自定义", comment: "")
        }
    }
}

// MARK: Task Persistance

struct DailyTask: Codable, Equatable, Identifiable {
    let id: UUID
    let task: MAATask
    var enabled: Bool
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
