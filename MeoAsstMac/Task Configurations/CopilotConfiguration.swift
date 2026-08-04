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
    var formation_index = 0
    var add_trust = false
    var ignore_requirements = false

    enum SupportUnitUsage: Int, CaseIterable, Codable {
        /// 不加助战干员
        case None = 0
        /// 如果仅缺一名干员则尝试补助战
        case WhenNeeded = 1
        /// 如果仅缺一名干员则尝试补助战，如无缺失则使用指定助战干员
        case Specific = 2
        /// 如果仅缺一名干员则尝试补助战，如无缺失则随机加一个助战干员
        case Random = 3
        
        var description: String {
            switch self {
            case .None:
                return NSLocalizedString("不借助战", comment: "")
            case .WhenNeeded:
                return NSLocalizedString("补漏", comment: "")
            case .Specific:
                return NSLocalizedString("指定", comment: "")
            case .Random:
                return NSLocalizedString("随机", comment: "")
            }
        }
    }
    
    var support_unit_usage: SupportUnitUsage = .None
    var support_unit_name = ""
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
