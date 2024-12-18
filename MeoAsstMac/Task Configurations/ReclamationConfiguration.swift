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
    var tool_to_craft = "荧光棒"
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

    var toolToCraftEnabled: Bool {
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
