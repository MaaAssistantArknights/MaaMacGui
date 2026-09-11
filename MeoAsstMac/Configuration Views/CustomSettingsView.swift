//
//  CustomSettingsView.swift
//  MAA
//
//  Created by zhangweijian on 11/9/2026.
//

import SwiftUI

struct CustomSettingsView: View {
    @Binding var config: CustomConfiguration

    var body: some View {
        Form {
            TextField(String(localized: "任务名"), text: $config.taskList, axis: .vertical)
                .lineLimit(3...6)

            if !config.parsedTaskNames.isEmpty {
                Text(formattedTaskNames)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Text(String(localized: "以逗号分隔的任务名列表，将执行第一个匹配的任务及其后续链。示例：TaskA, TaskB → 运行 TaskA（若未匹配则尝试 TaskB）"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var formattedTaskNames: String {
        "[" + config.parsedTaskNames.map { "\"\($0)\"" }.joined(separator: ", ") + "]"
    }
}

struct CustomSettings_Preview: PreviewProvider {
    static var previews: some View {
        CustomSettingsView(config: .constant(.init()))
    }
}
