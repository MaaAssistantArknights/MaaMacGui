//
//  CustomConfiguration.swift
//  MAA
//
//  Created by zhangweijian on 11/9/2026.
//

import Foundation

struct CustomTaskParams: Encodable {
    let task_names: [String]
}

struct CustomConfiguration: MAATaskConfiguration {
    var type: MAATaskType { .Custom }

    var taskList: String

    var title: String {
        type.description
    }

    var subtitle: String {
        let names = parsedTaskNames
        if names.isEmpty {
            return String(localized: "未填写任务名")
        }
        return names.joined(separator: " ")
    }

    var summary: String { "" }

    var projectedTask: MAATask {
        .custom(self)
    }

    /// 解析用户输入的任务名列表，兼容全角/半角逗号与换行分隔（对照 WPF TaskName 的逗号拆分 + Trim + RemoveEmptyEntries）。
    var parsedTaskNames: [String] {
        taskList
            .replacingOccurrences(of: "，", with: ",")
            .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == "\r" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    typealias Params = CustomTaskParams

    var params: CustomTaskParams {
        CustomTaskParams(task_names: parsedTaskNames)
    }
}

extension CustomConfiguration {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.taskList = try container.decodeIfPresent(String.self, forKey: .taskList) ?? ""
    }
}
