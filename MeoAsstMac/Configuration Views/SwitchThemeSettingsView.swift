//
//  SwitchThemeSettingsView.swift
//  MAA
//
//  Created by zhangweijian on 10/9/2026.
//

import SwiftUI

struct SwitchThemeSettingsView: View {
    @Binding var config: SwitchThemeConfiguration

    var body: some View {
        Form {
            Section {
                TextField("主题名称：", text: themesText, prompt: Text("多个主题用逗号分隔"))

                Text("填写游戏内主题列表中显示的名称，多个主题每次运行随机选择一个，留空则跳过更换主题。个别不常用字可能出现识别偏差导致主题未找到。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var themesText: Binding<String> {
        Binding {
            config.themes.joined(separator: "，")
        } set: { newValue in
            config.themes =
                newValue.split(whereSeparator: { $0 == "," || $0 == "，" })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
    }
}

struct SwitchThemeSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SwitchThemeSettingsView(config: .constant(.init()))
    }
}
