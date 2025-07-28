//
//  StartupConfiguration.swift
//  MAA
//
//  Created by hguandl on 16/4/2023.
//

import Foundation

struct StartupConfiguration: MAATaskConfiguration {
    var type: MAATaskType { .StartUp }

    var client_type: MAAClientChannel
    var start_game_enabled: Bool
    var account_name: String

    var title: String {
        type.description
    }

    var subtitle: String {
        return client_type.description
    }

    var summary: String {
        let startGame = start_game_enabled ? NSLocalizedString("自动启动", comment: "") : ""
        return "\(account_name) \(startGame)"
    }

    var projectedTask: MAATask {
        .startup(self)
    }

    typealias Params = Self

    var params: Self {
        self
    }
}

extension StartupConfiguration {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.client_type = try container.decodeIfPresent(MAAClientChannel.self, forKey: .client_type) ?? .Official
        self.start_game_enabled = try container.decodeIfPresent(Bool.self, forKey: .start_game_enabled) ?? false
        self.account_name = try container.decodeIfPresent(String.self, forKey: .account_name) ?? ""
    }
}

enum MAAClientChannel: String, Codable, CaseIterable, CustomStringConvertible {
    case Official
    case Bilibili
    case YoStarEN
    case YoStarJP
    case YoStarKR
    case txwy

    var description: String {
        switch self {
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
        ![MAAClientChannel.Official, .Bilibili].contains(self)
    }

    var appBundleName: String {
        switch self {
        case .Official, .Bilibili, .txwy:
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
        case .Official, .Bilibili:
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
