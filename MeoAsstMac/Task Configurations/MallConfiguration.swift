//
//  MallConfiguration.swift
//  MAA
//
//  Created by hguandl on 16/4/2023.
//

import Foundation

struct MallConfiguration: MAATaskConfiguration {
    var enable = true
    var shopping = true
    var buy_first = [NSLocalizedString("招聘许可", comment: ""), NSLocalizedString("龙门币", comment: "")]
    var blacklist = [NSLocalizedString("加急许可", comment: ""), NSLocalizedString("家具零件", comment: "")]
    var force_shopping_if_credit_full = true

    var title: String {
        MAATask.TypeName.Mall.description
    }

    var subtitle: String {
        if shopping {
            return NSLocalizedString("购物", comment: "")
        } else {
            return NSLocalizedString("不购物", comment: "")
        }
    }

    var summary: String {
        buy_first.joined(separator: ";")
    }
}
