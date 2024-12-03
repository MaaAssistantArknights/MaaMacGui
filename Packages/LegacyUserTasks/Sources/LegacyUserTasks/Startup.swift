//
//  Startup.swift
//  LegacyUserTasks
//
//  Created by hguandl on 16/4/2023.
//

import Foundation

@frozen public struct LegacyStartupConfiguration: Codable {
    public let enable: Bool
    public let client_type: LegacyMAAClientChannel
    public let start_game_enabled: Bool
}

@frozen public enum LegacyMAAClientChannel: String, Codable, CaseIterable {
    case `default` = ""
    case Official
    case Bilibili
    case YoStarEN
    case YoStarJP
    case YoStarKR
    case txwy
}
