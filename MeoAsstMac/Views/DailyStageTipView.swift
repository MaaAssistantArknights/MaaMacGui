//
//  DailyStageTipView.swift
//  MAA
//
//  Created by zhangweijian on 5/9/2026.
//

import SwiftUI

/// 内嵌于刷理智设置页底部的今日开放关卡展示。
struct DailyStageTipView: View {
    @AppStorage("MAAClientChannel") private var clientChannel = MAAClientChannel.Official
    @EnvironmentObject private var viewModel: MAAViewModel

    /// 活动关掉落 id 到物品名的映射（关卡数据保持原始文本，id 在此映射）。
    @State private var dropNames = [String: String]()

    var body: some View {
        LabeledContent {
            ScrollView {
                content.frame(maxWidth: .infinity, alignment: .leading)
            }
            .alignmentGuide(.firstTextBaseline) { d in
                d[.top]
            }
        } label: {
            VStack(alignment: .trailing) {
                Text("今日关卡小提示")
                    .font(.headline)
                Text("游戏内历法：\(weekdayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .alignmentGuide(.firstTextBaseline) { d in
                d[.top]
            }
        }
        .task(id: [clientChannel.rawValue] + pendingDropIds) { await loadDropNames() }
    }

    var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(tipRows) { row in
                switch row {
                case .headline(_, let text):
                    Text(text)
                        .font(.callout)
                case .stage(_, let code, let drop):
                    Text("\(code)：\(dropName(for: drop))")
                        .font(.callout)
                }
            }
        }
    }

    private var tipRows: [FightStage.TipRow] {
        FightStage.tips(
            for: .now,
            stageActivity: .init(channel: clientChannel, activities: viewModel.stageActivity))
    }

    private var weekdayName: String {
        clientChannel.calendar.weekdaySymbol(for: .now)
    }

    /// 作为 task id：活动数据 OTA 晚到时驱动映射重跑。
    private var pendingDropIds: [String] {
        tipRows.compactMap { row -> String? in
            guard case let .stage(_, _, drop) = row, !drop.isEmpty, drop.allSatisfy(\.isNumber) else { return nil }
            return drop
        }.sorted()
    }

    /// 掉落查无名字（core 未收录返回空串）时回退显示原始内容。
    private func dropName(for drop: String) -> String {
        if let name = dropNames[drop], !name.isEmpty { return name }
        return drop
    }

    private func loadDropNames() async {
        let ids = pendingDropIds
        guard !ids.isEmpty else { return }
        dropNames = await MAAProvider.shared.itemNames(for: ids)
    }
}

struct DailyStageTipView_Previews: PreviewProvider {
    static var previews: some View {
        Form {
            DailyStageTipView()
        }
        .environmentObject(MAAViewModel())
    }
}
