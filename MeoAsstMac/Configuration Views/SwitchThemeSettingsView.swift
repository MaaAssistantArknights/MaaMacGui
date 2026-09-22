//
//  SwitchThemeSettingsView.swift
//  MAA
//
//  Created by zhangweijian on 10/9/2026.
//

import SwiftUI

struct SwitchThemeSettingsView: View {
    @Environment(\.defaultMinListRowHeight) private var rowHeight

    @Binding var config: SwitchThemeConfiguration

    var body: some View {
        VStack(spacing: 30) {
            EditableTextList(title: "主题名称", texts: $config.themes)
                .frame(minHeight: 4 * rowHeight, maxHeight: 8 * rowHeight)

            Text("填写游戏内主题列表中显示的名称，多个主题每次运行随机选择一个，留空则跳过更换主题。个别不常用字可能出现识别偏差导致主题未找到。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

struct SwitchThemeSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SwitchThemeSettingsView(config: .constant(.init()))
    }
}
