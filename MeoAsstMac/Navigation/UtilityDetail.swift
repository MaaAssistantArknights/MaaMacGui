//
//  UtilityDetail.swift
//  MAA
//
//  Created by hguandl on 19/4/2023.
//

import SwiftUI

struct UtilityDetail: View {
    let entry: UtilityEntry?
    @State private var showInfo = true

    @ViewBuilder var content: some View {
        if showInfo {
            switch entry {
            case .recruit:
                RecruitView()
            case .depot:
                DepotView()
            case .oper:
                OperBoxView()
            case .video:
                VideoRecogView()
            case .gacha:
                GachaView()
            case .minigame:
                MiniGameView()
            case .maatools:
                MaaToolsView()
            case .none:
                Text("请选择工具项目")
            }
        } else {
            LogView()
        }
    }

    var body: some View {
        VStack {
            content
        }
        .padding()
        .toolbar {
            UtilityTitle(description: entry?.description)
            ToolbarItem {
                Picker("工具介绍", selection: $showInfo) {
                    Label("info", systemImage: "info")
                        .tag(true)
                        .help("工具介绍")
                    Label("日志", systemImage: "note.text")
                        .tag(false)
                        .help("运行日志")
                }
                .pickerStyle(.segmented)
            }
        }
    }
}

struct UtilityDetail_Previews: PreviewProvider {
    static var previews: some View {
        UtilityDetail(entry: .recruit)
            .environmentObject(MAAViewModel())
    }
}

private struct UtilityTitle: ToolbarContent {
    let description: String?

    var body: some ToolbarContent {
        let item = ToolbarItem {
            Text(description ?? String(localized: "实用工具"))
                .padding(.leading, 5)
                .font(.headline)
        }
        if #available(macOS 26.0, *) {
            item.sharedBackgroundVisibility(.hidden)
        } else {
            item
        }
    }
}
