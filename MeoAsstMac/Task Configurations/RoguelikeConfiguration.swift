//
//  RoguelikeConfiguration.swift
//  MAA
//
//  Created by hguandl on 16/4/2023.
//

import Foundation

struct RoguelikeConfiguration: MAATaskConfiguration {
    var enable = false
    var theme = RoguelikeTheme.Phantom
    var mode = 0
    var starts_count = 9999999
    var investment_enabled = true
    var investments_count = 999
    var stop_when_investment_full = false
    var squad = "指挥分队"
    var roles = "取长补短"
    var core_char = ""

    var title: String {
        MAATask.TypeName.Roguelike.description
    }

    var subtitle: String {
        return theme.description
    }

    var summary: String {
        switch mode {
        case 0:
            return NSLocalizedString("优先层数", comment: "")
        case 1:
            return NSLocalizedString("优先投资", comment: "")
        default:
            return NSLocalizedString("未知策略", comment: "")
        }
    }
}
