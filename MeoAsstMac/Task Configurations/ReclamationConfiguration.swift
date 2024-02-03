//
//  ReclamationConfiguration.swift
//  MAA
//
//  Created by hguandl on 19/4/2023.
//

import Foundation

struct ReclamationConfiguration: MAATaskConfiguration {
    var enable = false
    var task_names = ["Reclamation2"]

    var title: String {
        MAATask.TypeName.ReclamationAlgorithm.description
    }

    var subtitle: String {
        "测试版"
    }

    var summary: String {
        "请查看注意事项"
    }
}
