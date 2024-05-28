//
//  FightConfiguration.swift
//  MAA
//
//  Created by hguandl on 16/4/2023.
//

import Foundation

struct FightConfiguration: MAATaskConfiguration {
    var enable = true
    var stage = ""
    var medicine: Int?
    var expiring_medicine: Int?
    var stone: Int?
    var times: Int?
    var series: Int?
    var drops: [String: Int]?

    var report_to_penguin = false
    var penguin_id = ""
    var server = "CN"
    var client_type = ""
    var DrGrandet = false

    var title: String {
        MAATask.TypeName.Fight.description
    }

    var subtitle: String {
        if stage == "" {
            return NSLocalizedString("当前/上次", comment: "")
        } else {
            return stage
        }
    }

    var summary: String {
        var parts = [String]()

        if let medicine {
            parts.append(NSLocalizedString("理智药", comment: "") + "\(medicine)")
        }

        if let stone {
            parts.append(NSLocalizedString("源石", comment: "") + "\(stone)")
        }

        if let times {
            parts.append("\(times)" + NSLocalizedString("次", comment: ""))
        }

        return parts.joined(separator: ";")
    }
}
