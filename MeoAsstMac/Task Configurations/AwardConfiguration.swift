//
//  AwardConfiguration.swift
//  MAA
//
//  Created by hguandl on 16/4/2023.
//

import Foundation

struct AwardConfiguration: MAATaskConfiguration {
    var enable = true

    var title: String {
        MAATask.TypeName.Award.description
    }

    var subtitle: String {
        NSLocalizedString("日常任务 周常任务", comment: "")
    }

    var summary: String { "" }
}
