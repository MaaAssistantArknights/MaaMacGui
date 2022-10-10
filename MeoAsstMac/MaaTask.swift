//
//  MaaTask.swift
//  MeoAsstMac
//
//  Created by hguandl on 9/10/2022.
//

import Foundation

struct MaaTask: Codable {
    let key: TaskKey
    var enabled: Bool

    enum TaskKey: String, Codable {
        case StartUp
        case Recruit
        case Infrast
        case Fight
        case Visit
        case Mall
        case Award
        case Roguelike
    }

    static let defaults = [
        MaaTask(key: .StartUp, enabled: true),
        MaaTask(key: .Recruit, enabled: true),
        MaaTask(key: .Infrast, enabled: true),
        MaaTask(key: .Fight, enabled: true),
        MaaTask(key: .Visit, enabled: true),
        MaaTask(key: .Mall, enabled: true),
        MaaTask(key: .Award, enabled: true),
        MaaTask(key: .Roguelike, enabled: false)
    ]
}

extension MaaTask: CustomStringConvertible {
    var description: String {
        key.description
    }
}

extension MaaTask.TaskKey: CustomStringConvertible {
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
        case .Visit:
            return NSLocalizedString("访问好友", comment: "")
        case .Mall:
            return NSLocalizedString("收取信用及购物", comment: "")
        case .Award:
            return NSLocalizedString("领取日常奖励", comment: "")
        case .Roguelike:
            return NSLocalizedString("自动肉鸽", comment: "")
        }
    }
}
