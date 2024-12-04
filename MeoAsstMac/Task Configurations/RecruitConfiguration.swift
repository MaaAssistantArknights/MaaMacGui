//
//  RecruitConfiguration.swift
//  MAA
//
//  Created by hguandl on 16/4/2023.
//

import Foundation

struct RecruitConfiguration: MAATaskConfiguration {
    var refresh = true
    var select = [4, 5]
    var confirm = [3, 4, 5]
    var times = 4
    var set_time = true
    var expedite = false
    var skip_robot = true
    var recruitment_time = ["3": 540, "4": 540, "5": 540, "6": 540]

    var title: String {
        MAATask.TypeName.Recruit.description
    }

    var subtitle: String {
        if expedite {
            return NSLocalizedString("加急", comment: "")
        } else {
            return NSLocalizedString("不加急", comment: "")
        }
    }

    var summary: String {
        let levelString = confirm.map(String.init).joined(separator: ",")
        return "★\(levelString)"
    }

    var projectedTask: MAATask {
        .recruit(self)
    }

    typealias Params = Self

    var params: Self {
        self
    }

    static var recognition: RecruitConfiguration {
        .init(refresh: false, select: [4, 5, 6], confirm: [], times: 0)
    }
}
