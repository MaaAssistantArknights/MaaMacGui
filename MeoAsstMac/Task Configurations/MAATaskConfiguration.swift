//
//  MAATaskConfiguration.swift
//  MAA
//
//  Created by hguandl on 16/4/2023.
//

import SwiftUI

protocol MAATaskConfiguration: Codable & Hashable {
    var type: MAATaskType { get }

    var title: String { get }
    var subtitle: String { get }
    var summary: String { get }

    var projectedTask: MAATask { get }

    associatedtype Params: Encodable
    var params: Params { get }
}

extension MAATaskConfiguration {
    init() {
        let data = Data([0x7b, 0x7d])
        let decoder = JSONDecoder()
        self = try! decoder.decode(Self.self, from: data)
    }
}

// MARK: JSON TaskParams

extension MAAHandle {
    func appendTask(_ task: MAATask) throws -> Int32 {
        switch task {
        case .startup(let config):
            return try appendTask(config: config)
        case .closedown(let config):
            return try appendTask(config: config)
        case .recruit(let config):
            return try appendTask(config: config)
        case .infrast(let config):
            return try appendTask(config: config)
        case .fight(let config):
            return try appendTask(config: config)
        case .mall(let config):
            return try appendTask(config: config)
        case .award(let config):
            return try appendTask(config: config)
        case .roguelike(let config):
            return try appendTask(config: config)
        case .reclamation(let config):
            return try appendTask(config: config)
        }
    }

    func appendTask<T: MAATaskConfiguration>(config: T) throws -> Int32 {
        try appendTask(type: config.type, params: config.params.jsonString())
    }
}
