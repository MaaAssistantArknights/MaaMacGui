//
//  MAATaskConfiguration.swift
//  MAA
//
//  Created by hguandl on 16/4/2023.
//

import SwiftUI

protocol MAATaskConfiguration: Codable & Hashable {
    var title: String { get }
    var subtitle: String { get }
    var summary: String { get }

    var projectedTask: MAATask { get }

    associatedtype Params: Encodable
    var params: Params { get }
}

// MARK: JSON TaskParams

extension DailyTask {
    var params: String? {
        guard enabled else { return nil }
        switch task {
        case .startup(let config):
            return try? config.params.jsonString()
        case .closedown(let config):
            return try? config.params.jsonString()
        case .recruit(let config):
            return try? config.params.jsonString()
        case .infrast(let config):
            return try? config.params.jsonString()
        case .fight(let config):
            return try? config.params.jsonString()
        case .mall(let config):
            return try? config.params.jsonString()
        case .award(let config):
            return try? config.params.jsonString()
        case .roguelike(let config):
            return try? config.params.jsonString()
        case .reclamation(let config):
            return try? config.params.jsonString()
        }
    }
}
