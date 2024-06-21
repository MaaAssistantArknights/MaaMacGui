//
//  DepotView.swift
//  MAA
//
//  Created by hguandl on 18/4/2023.
//

import SwiftUI

struct DepotView: View {
    @EnvironmentObject private var viewModel: MAAViewModel

    var body: some View {
        VStack(spacing: 20) {
            List(viewModel.depot?.contents ?? [], id: \.self) { content in
                Text(content)
            }
            .animation(.default, value: viewModel.depot?.contents)

            HStack(spacing: 20) {
                Text("复制结果JSON至剪贴板：")

                Button("企鹅物流") {
                    copyToPasteboard(text: viewModel.depot?.arkplanner.data)
                    NSWorkspace.shared.open(URL(string: "https://penguin-stats.cn/planner")!)
                }
                Button("明日方舟工具箱") {
                    copyToPasteboard(text: viewModel.depot?.lolicon.data)
                    NSWorkspace.shared.open(URL(string: "https://arkntools.app/#/material")!)
                }
            }
            .disabled(viewModel.depot?.done != true)
        }
        .padding()
    }

    private func copyToPasteboard(text: String?) {
        guard let text else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

struct DepotView_Previews: PreviewProvider {
    static var previews: some View {
        DepotView()
            .environmentObject(MAAViewModel())
    }
}
