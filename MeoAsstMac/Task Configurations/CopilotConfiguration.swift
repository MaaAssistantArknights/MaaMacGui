//
//  CopilotConfiguration.swift
//  MAA
//
//  Created by hguandl on 17/4/2023.
//

import Foundation

struct UserAdditional: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var skill: Int
}

struct RegularCopilotConfiguration: Codable {
    var enable = true
    var filename: String
    var formation = false
    var add_trust = false
    var is_raid = false
    var loop_times = 1
    var use_sanity_potion = false
    var need_navigate = false
    var navigate_name: String?
    var user_additional: [UserAdditional]? = nil
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
    case sss(SSSCopilotConfiguration)

    var params: String? {
        switch self {
        case .regular(let config):
            return try? config.jsonString()
        case .sss(let config):
            return try? config.jsonString()
        }
    }
}
