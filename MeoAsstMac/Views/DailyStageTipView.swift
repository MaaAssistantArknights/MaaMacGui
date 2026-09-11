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
    }

    var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(openStages, id: \.code) { stage in
                Text("\(stage.code)：\(stage.drop)")
                    .font(.callout)
            }
        }
    }

    private var openStages: [(code: String, drop: String)] {
        FightStage.tips(for: .now, stageActivity: .init(channel: clientChannel, activities: nil))
    }

    private var weekdayName: String {
        clientChannel.calendar.weekdaySymbol(for: .now)
    }
}

struct DailyStageTipView_Previews: PreviewProvider {
    static var previews: some View {
        Form {
            DailyStageTipView()
        }
    }
}
