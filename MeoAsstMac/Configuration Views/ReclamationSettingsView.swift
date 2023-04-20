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
            Picker("模式", selection: config.mode) {
                Text("刷分与建造点，进入战斗直接退出").tag(0)
                Text("刷赤金，联络员买水后基地锻造").tag(1)
            }
        }
        .padding()
    }
}

//struct ReclamationSettingsView_Previews: PreviewProvider {
//    @State static var config: any MAATaskConfiguration = ReclamationConfiguration.default()
//    static var previews: some View {
//        ReclamationSettingsView(config: $config)
//    }
//}
