//
//  ReclamationConfiguration.swift
//  MAA
//
//  Created by hguandl on 19/4/2023.
//

import Foundation

struct ReclamationConfiguration: MAATaskConfiguration {
    var enable = false
    var theme = ReclamationTheme.tales
    var mode = 0
    var product = "荧光棒"

    var modes: [Int: String] {
        switch theme {
        case .fire:
            return [
                0: NSLocalizedString("刷分与建造点", comment: ""),
                1: NSLocalizedString("刷赤金", comment: ""),
            ]
        case .tales:
            return [
                0: NSLocalizedString("刷分与建造点", comment: ""),
                1: NSLocalizedString("制造物品并读档循环", comment: ""),
            ]
        }
    }

    var productEnabled: Bool {
        theme == .tales && mode == 1
    }

    var title: String {
        MAATask.TypeName.ReclamationAlgorithm.description
    }

    var subtitle: String {
        theme.description
    }

    var summary: String {
        modes[mode] ?? ""
    }
}

enum ReclamationTheme: Int, CaseIterable, Codable, CustomStringConvertible {
    case fire = 0
    case tales = 1

    var description: String {
        switch self {
        case .fire:
            return NSLocalizedString("沙中之火", comment: "")
        case .tales:
            return NSLocalizedString("沙洲遗闻", comment: "")
        }
    }
}
