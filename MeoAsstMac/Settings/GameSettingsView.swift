//
//  GameSettingsView.swift
//  MAA
//
//  Created by hguandl on 28/4/2023.
//

import SwiftUI

struct GameSettingsView: View {
    @EnvironmentObject private var viewModel: MAAViewModel

    var body: some View {
        VStack {
            Picker("客户端类型：", selection: $viewModel.clientChannel) {
                ForEach(MAAClientChannel.allCases, id: \.rawValue) { channel in
                    Text("\(channel.description)").tag(channel)
                }
            }
        }
        .padding()
    }
}

struct GameSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        GameSettingsView().environmentObject(MAAViewModel())
    }
}
