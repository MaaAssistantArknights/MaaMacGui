//
//  UtilityDetail.swift
//  MAA
//
//  Created by hguandl on 19/4/2023.
//

import SwiftUI

struct UtilityDetail: View {
    let entry: UtilityEntry?
    @State private var mode = UtilityDetailMode.tool

    var body: some View {
        VStack {
            switch mode {
            case .tool:
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
                    Text("请选择识别项目")
                }
            case .log:
                LogView()
            }
        }
        .padding()
        .toolbar {
            UtilityTitle(description: entry?.description)
            ToolbarItem {
                Picker("内容", selection: $mode) {
                    Label("工具", systemImage: "wrench.and.screwdriver").tag(UtilityDetailMode.tool)
                    Label("日志", systemImage: "note.text").tag(UtilityDetailMode.log)
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
            .environment(NewViewModel(parent: MAAViewModel()))
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

private enum UtilityDetailMode: Hashable {
    case tool
    case log
}
