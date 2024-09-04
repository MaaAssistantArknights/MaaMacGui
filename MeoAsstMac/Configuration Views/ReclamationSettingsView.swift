//
//  ReclamationSettingsView.swift
//  MAA
//
//  Created by hguandl on 16/4/2023.
//

import SwiftUI

struct ReclamationSettingsView: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    let id: UUID

    private var config: Binding<ReclamationConfiguration> {
        viewModel.taskConfig(id: id)
    }

    var body: some View {
        Form {
            Picker("主题：", selection: config.theme) {
                ForEach(ReclamationTheme.allCases, id: \.rawValue) { theme in
                    Text("\(theme.description)").tag(theme)
                }
            }

            Picker("策略：", selection: config.mode) {
                ForEach(config.wrappedValue.modes.sorted(by: <), id: \.key) { mode, desc in
                    Text(desc).tag(mode)
                }
            }

            if config.wrappedValue.toolToCraftEnabled {
                TextField("支援道具：", text: config.tool_to_craft)
                TextField("组装批次数：", value: config.num_craft_batches, format: .number)
                Picker("组装数量增加模式：", selection: config.increment_mode) {
                    ForEach(config.wrappedValue.increment_modes.sorted(by: <), id: \.key) { increment_mode, desc in
                        Text(desc).tag(increment_mode)
                    }
                }
            }
        }
        .animation(.default, value: config.wrappedValue.toolToCraftEnabled)
        .padding()
    }
}

struct ReclamationSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        ReclamationSettingsView(id: UUID())
            .environmentObject(MAAViewModel())
    }
}
