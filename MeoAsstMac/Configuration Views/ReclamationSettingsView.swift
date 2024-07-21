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

            if config.wrappedValue.productEnabled {
                TextField("物品：", text: config.product)
            }
        }
        .animation(.default, value: config.wrappedValue.productEnabled)
        .padding()
    }
}

struct ReclamationSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        ReclamationSettingsView(id: UUID())
            .environmentObject(MAAViewModel())
    }
}
