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
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                Text("目前生息演算的支持仍处于早期阶段，使用时请注意：")
                    .font(.title2)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom)

                Text("1. 不能在已经有存档的情况下使用")

                Text("2. 不能在编队中有干员的情况下使用（把所有编队清空即可）")

                Text("3. 必须在生息演算主界面开始任务（导航还没写）")
            }
            .padding()
        }
    }
}

struct ReclamationSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        ReclamationSettingsView(id: UUID())
            .environmentObject(MAAViewModel())
    }
}
