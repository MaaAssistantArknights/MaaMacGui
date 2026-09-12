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
    /// 先归一化换行：Swift 中 "\r\n" 是单个 grapheme cluster，split 谓词按 Character 比较匹配不到，需拆成 "\n" 再进入分隔。
    var parsedTaskNames: [String] {
        taskList
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "，", with: ",")
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
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
