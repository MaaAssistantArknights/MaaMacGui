//
//  MAATaskConfiguration.swift
//  MAA
//
//  Created by hguandl on 16/4/2023.
//

import SwiftUI

protocol MAATaskConfiguration: Codable & Hashable {
    var enable: Bool { get set }

    var title: String { get }
    var subtitle: String { get }
    var summary: String { get }

    init()
}

extension MAATaskConfiguration {
    func jsonStringIfEnabled() -> String? {
        guard enable else { return nil }

        return try? jsonString()
    }
}

// MARK: JSON TaskParams

extension MAATask {
    var params: String? {
        switch self {
        case .startup(let config):
            return config.jsonStringIfEnabled()
        case .closedown(let config):
            return config.jsonStringIfEnabled()
        case .recruit(let config):
            return config.jsonStringIfEnabled()
        case .infrast(let config):
            return config.jsonStringIfEnabled()
        case .fight(let config):
            return config.jsonStringIfEnabled()
        case .mall(let config):
            return config.jsonStringIfEnabled()
        case .award(let config):
            return config.jsonStringIfEnabled()
        case .roguelike(let config):
            return config.jsonStringIfEnabled()
        case .reclamation(let config):
            return config.jsonStringIfEnabled()
        }
    }
}

// MARK: Type-erased TaskConfig

extension MAATask {
    func unwrapConfig<T: MAATaskConfiguration>() -> T {
        switch self {
        case .startup(let config):
            return config as? T ?? .init()
        case .closedown(let config):
            return config as? T ?? .init()
        case .recruit(let config):
            return config as? T ?? .init()
        case .infrast(let config):
            return config as? T ?? .init()
        case .fight(let config):
            return config as? T ?? .init()
        case .mall(let config):
            return config as? T ?? .init()
        case .award(let config):
            return config as? T ?? .init()
        case .roguelike(let config):
            return config as? T ?? .init()
        case .reclamation(let config):
            return config as? T ?? .init()
        }
    }

    init<T: MAATaskConfiguration>(config: T) {
        switch config {
        case let newConfig as StartupConfiguration:
            self = .startup(newConfig)
        case let newConfig as ClosedownConfiguration:
            self = .closedown(newConfig)
        case let newConfig as RecruitConfiguration:
            self = .recruit(newConfig)
        case let newConfig as InfrastConfiguration:
            self = .infrast(newConfig)
        case let newConfig as FightConfiguration:
            self = .fight(newConfig)
        case let newConfig as MallConfiguration:
            self = .mall(newConfig)
        case let newConfig as AwardConfiguration:
            self = .award(newConfig)
        case let newConfig as RoguelikeConfiguration:
            self = .roguelike(newConfig)
        case let newConfig as ReclamationConfiguration:
            self = .reclamation(newConfig)
        default:
            self = .closedown(.init())
        }
    }
}
