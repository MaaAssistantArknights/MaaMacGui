//
//  CopilotConfiguration.swift
//  MAA
//
//  Created by hguandl on 17/4/2023.
//

import Foundation

struct RegularCopilotConfiguration: Codable, Hashable {
    var enable = true

    var filename: String

    struct CopilotItem: Codable, Hashable {
        let filename: String
        let stage_name: String
        let is_raid: Bool
    }

    var copilot_list: [CopilotItem]

    var loop_times = 1

    var use_sanity_potion = false

    var formation = false
    var formation_index = 0
    static let formationCount = 4

    struct UserUnit: Codable, Hashable {
        let name: String
        let skill: Int
    }

    var user_additional = [UserUnit]()

    var add_trust = false
    var ignore_requirements = false

    enum SupportUnitUsage: Int, CaseIterable, Codable {
        /// 不加助战干员
        case none = 0
        /// 如果仅缺一名干员则尝试补助战
        case whenNeeded = 1
        /// 如果仅缺一名干员则尝试补助战，如无缺失则随机加一个助战干员
        case random = 3
        /// 如果仅缺一名干员则尝试补助战，如无缺失则使用指定助战干员
        case specific = 2

        var description: String {
            switch self {
            case .none:
                return String(localized: "不借", comment: "")
            case .whenNeeded:
                return String(localized: "补漏", comment: "")
            case .specific:
                return String(localized: "指定", comment: "")
            case .random:
                return String(localized: "随机", comment: "")
            }
        }
    }

    var support_unit_usage: SupportUnitUsage = .none
    var support_unit_name = ""
}

typealias SSSCopilotConfiguration = RegularCopilotConfiguration

extension RegularCopilotConfiguration {
    init(filename: String) {
        self.init(filename: filename, copilot_list: [])
    }

    init(copilotList: [CopilotItem]) {
        self.init(filename: "", copilot_list: copilotList)
    }
}

struct VideoRecognitionConfiguration: Codable {
    var enable = true
    var filename: String

    var params: String? {
        try? jsonString()
    }
}

enum CopilotConfiguration: Hashable {
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
