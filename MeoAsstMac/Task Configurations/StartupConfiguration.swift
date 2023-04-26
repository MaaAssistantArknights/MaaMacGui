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
            return "不选择"
        case .Official:
            return "官服"
        case .Bilibili:
            return "Bilibili服"
        case .YoStarEN:
            return "国际服（YoStarEN）"
        case .YoStarJP:
            return "日服（YoStarJP）"
        case .YoStarKR:
            return "韩服（YoStarKR）"
        case .txwy:
            return "繁中服（txwy）"
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
}
