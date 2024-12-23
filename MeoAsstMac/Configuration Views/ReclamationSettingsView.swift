//
//  ReclamationSettingsView.swift
//  MAA
//
//  Created by hguandl on 16/4/2023.
//

import SwiftUI

struct ReclamationSettingsView: View {
    @Binding var config: ReclamationConfiguration
    @State private var toolsToCraft: String = ""

    var body: some View {
        Form {
            Picker("主题：", selection: $config.theme) {
                ForEach(ReclamationTheme.allCases, id: \.rawValue) { theme in
                    Text("\(theme.description)").tag(theme)
                }
            }

            Picker("策略：", selection: $config.mode) {
                ForEach(config.modes.sorted(by: <), id: \.key) { mode, desc in
                    Text(desc).tag(mode)
                }
            }

            if config.toolsToCraftEnabled {
                TextField("支援道具：", text: $toolsToCraft)
                    .onChange(of: toolsToCraft) { newValue in
                        config.tools_to_craft = newValue.split(separator: ";").map {
                            $0.trimmingCharacters(in: .whitespaces)
                        }
                    }
                    .onAppear {
                        toolsToCraft = config.tools_to_craft.joined(separator: "; ")
                    }
                TextField("组装批次数：", value: $config.num_craft_batches, format: .number)
                Picker("组装数量增加模式：", selection: $config.increment_mode) {
                    ForEach(config.increment_modes.sorted(by: <), id: \.key) { increment_mode, desc in
                        Text(desc).tag(increment_mode)
                    }
                }
            }
        }
        .animation(.default, value: config.toolsToCraftEnabled)
        .padding()
    }
}

struct ReclamationSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        ReclamationSettingsView(config: .constant(.init()))
    }
}
