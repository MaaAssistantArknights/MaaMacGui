//
//  CopilotListContent.swift
//  MAA
//
//  Created by hguandl on 2026/8/7.
//

import SwiftUI

struct CopilotListContent: View {
    let context: CopilotContext

    var body: some View {
        @Bindable var context = context
        ForEach($context.copilotList) { $item in
            Toggle(item.description, isOn: $item.isOn)
        }
        HStack {
            Button("全选") {
                $context.copilotList.forEach { $i in i.isOn = true }
            }
            .buttonStyle(.borderedProminent)
            Button("取消") {
                $context.copilotList.forEach { $i in i.isOn = false }
            }
            Button("清除") {
                context.copilotList.removeAll()
            }
            .tint(.red)
        }
        .controlSize(.small)
    }
}

extension CopilotContext.ListItem: CustomStringConvertible {
    var description: String {
        if isRaid == true {
            return "\(stageCode)\(String(localized: "（突袭）"))"
        } else {
            return stageCode
        }
    }
}

#Preview {
    @Previewable @State var selection = URL?.none
    NavigationSplitView {
        EmptyView()
    } content: {
        List(selection: $selection) {
            CopilotListContent(context: .init())
        }
    } detail: {
        EmptyView()
    }
}
