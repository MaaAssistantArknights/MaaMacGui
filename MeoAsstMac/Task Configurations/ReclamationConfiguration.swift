//
//  ReclamationConfiguration.swift
//  MAA
//
//  Created by hguandl on 19/4/2023.
//

import Foundation

struct ReclamationConfiguration: MAATaskConfiguration {
    var enable = false
    var mode = 0

    var title: String {
        MAATask.TypeName.ReclamationAlgorithm.description
    }

    var subtitle: String {
        switch mode {
        case 0:
            return NSLocalizedString("刷分与建造点", comment: "")
        case 1:
            return NSLocalizedString("刷赤金", comment: "")
        default:
            return NSLocalizedString("未知策略", comment: "")
        }
    }

    var summary: String {
        switch mode {
        case 0:
            return NSLocalizedString("进入战斗直接退出", comment: "")
        case 1:
            return NSLocalizedString("联络员买水后基地锻造", comment: "")
        default:
            return NSLocalizedString("", comment: "")
        }
    }
}
