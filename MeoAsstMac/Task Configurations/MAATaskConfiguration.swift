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

// MARK: JSON TaskParams

extension MAATask {
    var params: String? {
        switch self {
        case .startup(let config):
            return jsonString(config)
        case .recruit(let config):
            return jsonString(config)
        case .infrast(let config):
            return jsonString(config)
        case .fight(let config):
            return jsonString(config)
        case .mall(let config):
            return jsonString(config)
        case .award(let config):
            return jsonString(config)
        case .roguelike(let config):
            return jsonString(config)
        case .reclamation(let config):
            return jsonString(config)
        }
    }
}

private func jsonString<C: MAATaskConfiguration>(_ config: C) -> String? {
    guard config.enable else { return nil }

    let encoder = JSONEncoder()
    encoder.outputFormatting = .withoutEscapingSlashes

    guard let data = try? encoder.encode(config) else { return nil }
    return String(data: data, encoding: .utf8)
}

// MARK: Type-erased TaskConfig

extension MAATask {
    func unwrapConfig<T: MAATaskConfiguration>() -> T {
        switch self {
        case .startup(let config):
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
