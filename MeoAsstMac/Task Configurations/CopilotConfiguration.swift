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

struct SSSCopilotConfiguration: Codable {
    var enable = true
    var filename: String
    var loop_times = 1
}

/// One element of the `copilot_list` array sent to the core.
struct CopilotListItem: Codable {
    var filename: String
    var stage_name: String
    var is_raid: Bool
}

/// Parameters for a copilot-list (作业集) run. Field names match the core's `Copilot`
/// task params built by the Windows `AsstCopilotTask`.
struct CopilotListConfiguration: Codable {
    var enable = true
    var copilot_list: [CopilotListItem]
    var formation = true
    var add_trust = false
    var support_unit_usage = 0
    var use_sanity_potion = false
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
    case sss(SSSCopilotConfiguration)
    case list(CopilotListConfiguration)

    var params: String? {
        switch self {
        case .regular(let config):
            return try? config.jsonString()
        case .sss(let config):
            return try? config.jsonString()
        case .list(let config):
            return try? config.jsonString()
        }
    }
}
