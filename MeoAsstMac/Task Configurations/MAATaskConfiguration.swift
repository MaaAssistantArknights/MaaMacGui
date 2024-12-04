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

    var projectedTask: MAATask { get }
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
