//
//  CopilotListContent.swift
//  MAA
//
//  Created by hguandl on 2026/8/7.
//

import SwiftUI

struct CopilotListContent: View {
    @Bindable var context: CopilotContext

    var body: some View {
        ForEach($context.copilotList) { $item in
            let itemID = item.id
            let index = context.copilotList.firstIndex { $0.id == itemID } ?? 0
            HStack {
                Toggle(isOn: $item.isOn) {
                    HStack(spacing: 6) {
                        Text(stageTitle(item))
                            .fontWeight(.medium)
                            .lineLimit(1)
                        if showsStageName(item) {
                            Text(item.stageName)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if item.isRaid == true {
                            Text("突袭")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .help(item.description)
                Button {
                    move(itemID, by: -1)
                } label: {
                    Image(systemName: "arrow.up")
                }
                .disabled(index == 0)
                .help("上移作业")
                Button {
                    move(itemID, by: 1)
                } label: {
                    Image(systemName: "arrow.down")
                }
                .disabled(index >= context.copilotList.count - 1)
                .help("下移作业")
                Button {
                    context.copilotList.removeAll { $0.id == itemID }
                } label: {
                    Image(systemName: "xmark")
                }
                .help("移除作业")
            }
            .buttonStyle(.borderless)
        }
    }

    private func stageTitle(_ item: CopilotContext.ListItem) -> String {
        if let code = MAACopilot.navigationOverride(code: item.stageCode) {
            return code
        }
        if !item.stageName.isEmpty {
            return item.stageName
        }
        return item.stageCode
    }

    private func showsStageName(_ item: CopilotContext.ListItem) -> Bool {
        let title = stageTitle(item)
        return !item.stageName.isEmpty && item.stageName != title && !MAACopilot.isDecimalID(item.stageName)
    }

    private func move(_ id: CopilotContext.ItemID, by offset: Int) {
        guard let index = context.copilotList.firstIndex(where: { $0.id == id }),
            context.copilotList.indices.contains(index + offset)
        else {
            return
        }
        context.copilotList.swapAt(index, index + offset)
    }
}

struct CopilotListControls: View {
    @Bindable var context: CopilotContext

    var body: some View {
        HStack(spacing: 12) {
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
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .onTapGesture {
            context.selection = nil
        }
    }
}

extension CopilotContext.ListItem: CustomStringConvertible {
    var description: String {
        let code = MAACopilot.navigationOverride(code: stageCode)
        let stage: String
        if let code {
            stage = stageName.isEmpty || stageName == code ? code : "\(code) · \(stageName)"
        } else if !stageName.isEmpty, !MAACopilot.isDecimalID(stageName) {
            stage = stageName
        } else {
            stage = stageCode
        }
        if isRaid == true {
            return "\(stage)\(String(localized: "（突袭）"))"
        } else {
            return stage
        }
    }
}

#Preview {
    @Previewable @State var selection = URL?.none
    @Previewable @State var context = CopilotContext()
    NavigationSplitView {
        EmptyView()
    } content: {
        List(selection: $selection) {
            CopilotListContent(context: context)
        }
        .safeAreaInset(edge: .bottom) {
            CopilotListControls(context: context)
        }
    } detail: {
        EmptyView()
    }
}
