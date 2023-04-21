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
        jsonString(self)
    }
}

enum CopilotConfiguration {
    case regular(RegularCopilotConfiguration)
    case sss(SSSCopilotConfiguration)

    var params: String? {
        switch self {
        case .regular(let config):
            return jsonString(config)
        case .sss(let config):
            return jsonString(config)
        }
    }
}

private func jsonString<C: Encodable>(_ config: C) -> String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .withoutEscapingSlashes

    guard let data = try? encoder.encode(config) else { return nil }
    return String(data: data, encoding: .utf8)
}
