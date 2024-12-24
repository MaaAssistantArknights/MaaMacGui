//
//  ReclamationConfiguration.swift
//  MAA
//
//  Created by hguandl on 19/4/2023.
//

import Foundation

struct ReclamationConfiguration: MAATaskConfiguration {
    var type: MAATaskType { .Reclamation }

    var theme = ReclamationTheme.tales
    var mode = 0
    var tools_to_craft = ["荧光棒"]
    var num_craft_batches = 16
    var increment_mode = 0

    var modes: [Int: String] {
        switch theme {
        case .fire:
            return [
                0: NSLocalizedString("刷分与建造点", comment: ""),
                1: NSLocalizedString("刷赤金", comment: ""),
            ]
        case .tales:
            return [
                0: NSLocalizedString("无存档，通过进出关卡刷生息点数", comment: ""),
                1: NSLocalizedString("有存档，通过组装支援道具刷生息点数，组装完成后将会跳到下一个量定日并读取前一个量定日的存档", comment: ""),
            ]
        }
    }

    var increment_modes: [Int: String] {
        return [
            0: NSLocalizedString("点击加号按钮", comment: ""),
            1: NSLocalizedString("按住加号按钮", comment: ""),
        ]
    }

    var toolsToCraftEnabled: Bool {
        theme == .tales && mode == 1
    }

    var title: String {
        type.description
    }

    var subtitle: String {
        theme.description
    }

    var summary: String {
        modes[mode] ?? ""
    }

    var projectedTask: MAATask {
        .reclamation(self)
    }

    typealias Params = Self

    var params: Self {
        self
    }
}

extension ReclamationConfiguration {
    enum CodingKeys: String, CodingKey {
        case theme
        case mode
        case tool_to_craft
        case tools_to_craft
        case num_craft_batches
        case increment_mode
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.theme = try container.decode(ReclamationTheme.self, forKey: .theme)
        self.mode = try container.decode(Int.self, forKey: .mode)
        self.num_craft_batches = try container.decode(Int.self, forKey: .num_craft_batches)
        self.increment_mode = try container.decode(Int.self, forKey: .increment_mode)
        do {
            self.tools_to_craft = try container.decode([String].self, forKey: .tools_to_craft)
        } catch {
            self.tools_to_craft = [try container.decode(String.self, forKey: .tool_to_craft)]
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(theme, forKey: .theme)
        try container.encode(mode, forKey: .mode)
        try container.encode(tools_to_craft, forKey: .tools_to_craft)
        try container.encode(num_craft_batches, forKey: .num_craft_batches)
        try container.encode(increment_mode, forKey: .increment_mode)
    }
}

enum ReclamationTheme: String, CaseIterable, Codable, CustomStringConvertible {
    case fire = "Fire"
    case tales = "Tales"

    var description: String {
        switch self {
        case .fire:
            return NSLocalizedString("沙中之火", comment: "")
        case .tales:
            return NSLocalizedString("沙洲遗闻", comment: "")
        }
    }
}
