//
//  MAATask.swift
//  MAA
//
//  Created by hguandl on 15/4/2023.
//

import SwiftUI

enum MAATask: Codable, Equatable {
    case startup(StartupConfiguration)
    case recruit(RecruitConfiguration)
    case infrast(InfrastConfiguration)
    case fight(FightConfiguration)
    case mall(MallConfiguration)
    case award(AwardConfiguration)
    case roguelike(RoguelikeConfiguration)
    case reclamation(ReclamationConfiguration)

    enum TypeName: String {
        case StartUp
        case Recruit
        case Infrast
        case Fight
        case Mall
        case Award
        case Roguelike
        case Copilot
        case SSSCopilot
        case Depot
        case ReclamationAlgorithm
        case VideoRecognition
        case OperBox
    }

    static let defaults: [MAATask] = [
        .startup(.init()),
        .recruit(.init()),
        .infrast(.init()),
        .fight(.init()),
        .mall(.init()),
        .award(.init()),
        .roguelike(.init()),
    ]

    init(type: TypeName) {
        switch type {
        case .StartUp:
            self = .startup(.init())
        case .Recruit:
            self = .recruit(.init())
        case .Infrast:
            self = .infrast(.init())
        case .Fight:
            self = .fight(.init())
        case .Mall:
            self = .mall(.init())
        case .Award:
            self = .award(.init())
        case .Roguelike:
            self = .roguelike(.init())
        case .ReclamationAlgorithm:
            self = .reclamation(.init())
        default:
            self = .award(.init())
        }
    }
}

// MARK: Task Type

extension MAATask {
    var typeName: TypeName {
        switch self {
        case .startup:
            return .StartUp
        case .recruit:
            return .Recruit
        case .infrast:
            return .Infrast
        case .fight:
            return .Fight
        case .mall:
            return .Mall
        case .award:
            return .Award
        case .roguelike:
            return .Roguelike
        case .reclamation:
            return .ReclamationAlgorithm
        }
    }
}

extension MAATask.TypeName: Codable, CustomStringConvertible {
    var description: String {
        switch self {
        case .StartUp:
            return NSLocalizedString("开始唤醒", comment: "")
        case .Recruit:
            return NSLocalizedString("自动公招", comment: "")
        case .Infrast:
            return NSLocalizedString("基建换班", comment: "")
        case .Fight:
            return NSLocalizedString("刷理智", comment: "")
        case .Mall:
            return NSLocalizedString("收取信用及购物", comment: "")
        case .Award:
            return NSLocalizedString("领取日常奖励", comment: "")
        case .Roguelike:
            return NSLocalizedString("自动肉鸽", comment: "")
        case .Copilot:
            return NSLocalizedString("自动抄作业", comment: "")
        case .SSSCopilot:
            return NSLocalizedString("自动抄保全作业", comment: "")
        case .Depot:
            return NSLocalizedString("仓库识别", comment: "")
        case .ReclamationAlgorithm:
            return NSLocalizedString("生息演算", comment: "")
        case .VideoRecognition:
            return NSLocalizedString("视频识别", comment: "")
        case .OperBox:
            return NSLocalizedString("干员识别", comment: "")
        }
    }

    static var daily: [MAATask.TypeName] {
        [.Recruit, .Infrast, .Fight, .Mall, .Award, .Roguelike]
    }
}

// MARK: - Task Overview

extension MAATask {
    var enabled: Bool {
        get {
            switch self {
            case .startup(let config):
                return config.enable
            case .recruit(let config):
                return config.enable
            case .infrast(let config):
                return config.enable
            case .fight(let config):
                return config.enable
            case .mall(let config):
                return config.enable
            case .award(let config):
                return config.enable
            case .roguelike(let config):
                return config.enable
            case .reclamation(let config):
                return config.enable
            }
        }
        set {
            switch self {
            case .startup(var config):
                config.enable = newValue
                self = .startup(config)
            case .recruit(var config):
                config.enable = newValue
                self = .recruit(config)
            case .infrast(var config):
                config.enable = newValue
                self = .infrast(config)
            case .fight(var config):
                config.enable = newValue
                self = .fight(config)
            case .mall(var config):
                config.enable = newValue
                self = .mall(config)
            case .award(var config):
                config.enable = newValue
                self = .award(config)
            case .roguelike(var config):
                config.enable = newValue
                self = .roguelike(config)
            case .reclamation(var config):
                config.enable = newValue
                self = .reclamation(config)
            }
        }
    }

    typealias Overview = (title: String, subtitle: String, summary: String)

    var overview: Overview {
        switch self {
        case .startup(let config):
            return (config.title, config.subtitle, config.summary)
        case .recruit(let config):
            return (config.title, config.subtitle, config.summary)
        case .infrast(let config):
            return (config.title, config.subtitle, config.summary)
        case .fight(let config):
            return (config.title, config.subtitle, config.summary)
        case .mall(let config):
            return (config.title, config.subtitle, config.summary)
        case .award(let config):
            return (config.title, config.subtitle, config.summary)
        case .roguelike(let config):
            return (config.title, config.subtitle, config.summary)
        case .reclamation(let config):
            return (config.title, config.subtitle, config.summary)
        }
    }
}

// MARK: Task Persistance

extension MAAViewModel {
    func writeBack(_ newValue: OrderedStore<MAATask>) {
        let data = try? PropertyListEncoder().encode(newValue)
        try? data?.write(to: tasksURL)
    }
}
