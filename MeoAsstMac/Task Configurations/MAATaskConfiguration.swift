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
        if let newConfig = config as? StartupConfiguration {
            self = .startup(newConfig)
        } else if let newConfig = config as? ClosedownConfiguration {
            self = .closedown(newConfig)
        } else if let newConfig = config as? RecruitConfiguration {
            self = .recruit(newConfig)
        } else if let newConfig = config as? InfrastConfiguration {
            self = .infrast(newConfig)
        } else if let newConfig = config as? FightConfiguration {
            self = .fight(newConfig)
        } else if let newConfig = config as? MallConfiguration {
            self = .mall(newConfig)
        } else if let newConfig = config as? AwardConfiguration {
            self = .award(newConfig)
        } else if let newConfig = config as? RoguelikeConfiguration {
            self = .roguelike(newConfig)
        } else if let newConfig = config as? ReclamationConfiguration {
            self = .reclamation(newConfig)
        } else {
            self = .award(.init())
        }
    }
}
