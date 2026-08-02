//
//  CopilotConfiguration.swift
//  MAA
//
//  Created by hguandl on 17/4/2023.
//

import Foundation

struct RegularCopilotConfiguration: Codable {
    var enable = true
    var filename: String
    var formation = false
    var add_trust = false
}

struct RegularCopilotListConfiguration: Codable {
    var enable = true
    var copilot_list: [CopilotListItem]
    var formation = false
    var add_trust = false
}

struct CopilotListItem: Codable, Equatable {
    var filename: String
    var stage_name: String
    var is_raid = false
}

struct SSSCopilotConfiguration: Codable {
    var enable = true
    var filename: String
    var loop_times = 1
}

struct VideoRecognitionConfiguration: Codable {
    var enable = true
    var filename: String

    var params: String? {
        try? jsonString()
    }
}

enum CopilotConfiguration {
    case regular(RegularCopilotConfiguration)
    case regularList(RegularCopilotListConfiguration)
    case sss(SSSCopilotConfiguration)

    var params: String? {
        switch self {
        case .regular(let config):
            return try? config.jsonString()
        case .regularList(let config):
            return try? config.jsonString()
        case .sss(let config):
            return try? config.jsonString()
        }
    }

    func applyingCommonOptions(formation: Bool, addTrust: Bool) -> Self {
        switch self {
        case .regular(var config):
            config.formation = formation
            config.add_trust = addTrust
            return .regular(config)
        case .regularList(var config):
            config.formation = formation
            config.add_trust = addTrust
            return .regularList(config)
        case .sss:
            return self
        }
    }
}
