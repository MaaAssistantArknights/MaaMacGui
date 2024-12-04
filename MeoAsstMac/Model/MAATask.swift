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

    enum TypeName: String {
        case StartUp
        case CloseDown
        case Recruit
        case Infrast
        case Fight
        case Mall
        case Award
        case Roguelike
        case Copilot
        case SSSCopilot
        case Depot
        case Reclamation
        case VideoRecognition
        case OperBox
        case Custom
    }

    static let defaults: [MAATask] = [
        .startup(.init()),
        .recruit(.init()),
        .infrast(.init()),
        .fight(.init()),
        .mall(.init()),
        .award(.init()),
        .roguelike(.init()),
        .reclamation(.init()),
        .closedown(.init()),
    ]

    init(type: TypeName) {
        switch type {
        case .StartUp:
            self = .startup(.init())
        case .CloseDown:
            self = .closedown(.init())
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
        case .Reclamation:
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
        case .closedown:
            return .CloseDown
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
            return .Reclamation
        }
    }
}

extension MAATask.TypeName: Codable, CustomStringConvertible {
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

    static var daily: [MAATask.TypeName] {
        [.Recruit, .Infrast, .Fight, .Mall, .Award, .Roguelike, .Reclamation, .CloseDown]
    }
}

// MARK: Task Persistance

struct DailyTask: Codable, Equatable, Identifiable {
    let id: UUID
    let task: MAATask
    var enabled: Bool
}

extension DailyTask {
    init(_ task: MAATask) {
        switch task {
        case .roguelike, .reclamation:
            self.init(id: UUID(), task: task, enabled: false)
        default:
            self.init(id: UUID(), task: task, enabled: true)
        }
    }
}

extension Array where Element == DailyTask {
    subscript(_ id: UUID) -> MAATask? {
        get {
            first { $0.id == id }?.task
        }
        set {
            if let newValue, let index = firstIndex(where: { $0.id == id }) {
                self[index] = .init(id: id, task: newValue, enabled: self[index].enabled)
            }
        }
    }

    func firstIndex(id: UUID) -> Int? {
        firstIndex { $0.id == id }
    }

    mutating func append(_ task: MAATask) {
        append(.init(task))
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
