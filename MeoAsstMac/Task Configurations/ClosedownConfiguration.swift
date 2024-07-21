//
//  ClosedownConfiguration.swift
//  MAA
//
//  Created by hguandl on 2024/7/22.
//

import Foundation

struct ClosedownConfiguration: MAATaskConfiguration {
    var enable = true

    var title: String {
        MAATask.TypeName.CloseDown.description
    }

    var subtitle: String {
        NSLocalizedString("请确保这是最后一个任务", comment: "")
    }

    var summary: String {
        ""
    }
}
