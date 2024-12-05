//
//  StartupConfiguration.swift
//  MAA
//
//  Created by hguandl on 16/4/2023.
//

import Foundation

struct StartupConfiguration: MAATaskConfiguration {
    var enable = true
    var client_type = MAAClientChannel.default
    var start_game_enabled = false

    var title: String {
        MAATask.TypeName.StartUp.description
    }

    var subtitle: String {
        return client_type.description
    }

    var summary: String {
        if start_game_enabled {
            return NSLocalizedString("自动启动", comment: "")
        } else {
            return ""
        }
    }

    var projectedTask: MAATask {
        .startup(self)
    }

    typealias Params = Self

    var params: Self {
        self
    }
}

enum MAAClientChannel: String, Codable, CaseIterable, CustomStringConvertible {
    case `default` = ""
    case Official
    case Bilibili
    case YoStarEN
    case YoStarJP
    case YoStarKR
    case txwy

    var description: String {
        switch self {
        case .default:
            return NSLocalizedString("不选择", comment: "")
        case .Official:
            return NSLocalizedString("官服", comment: "")
        case .Bilibili:
            return NSLocalizedString("Bilibili服", comment: "")
        case .YoStarEN:
            return NSLocalizedString("国际服（YoStarEN）", comment: "")
        case .YoStarJP:
            return NSLocalizedString("日服（YoStarJP）", comment: "")
        case .YoStarKR:
            return NSLocalizedString("韩服（YoStarKR）", comment: "")
        case .txwy:
            return NSLocalizedString("繁中服（txwy）", comment: "")
        }
    }

    var isGlobal: Bool {
        ![MAAClientChannel.default, .Official, .Bilibili].contains(self)
    }

    var appBundleName: String {
        switch self {
        case .Official, .Bilibili, .txwy, .default:
            return "明日方舟.app"
        case .YoStarEN:
            return "Arknights.app"
        case .YoStarJP:
            return "アークナイツ.app"
        case .YoStarKR:
            return "명일방주.app"
        }
    }

    var appBundleID: String {
        switch self {
        case .Official, .Bilibili, .default:
            return "com.hypergryph.arknights"
        case .YoStarEN:
            return "com.YoStarEN.Arknights"
        case .YoStarJP:
            return "com.YoStarJP.Arknights"
        case .YoStarKR:
            return "com.YoStarKR.Arknights"
        case .txwy:
            return "tw.txwy.ios.arknights"
        }
    }
}
