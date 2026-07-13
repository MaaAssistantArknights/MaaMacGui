//
//  TodayStageTipView.swift
//  MAA
//

import SwiftUI

struct TodayStageTipView: View {
    @EnvironmentObject private var viewModel: MAAViewModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let summary = viewModel.stageCatalog.todaySummary(
                for: StageServer(channelRawValue: viewModel.clientChannel.rawValue),
                now: context.date,
                coreVersion: MAAProvider.version)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("今日关卡小提示")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.secondary)
                        .help("关卡开放状态按当前服务器时区及凌晨 4 点刷新")
                }

                ForEach(summary.localizedTipKeys, id: \.self) { key in
                    Text(LocalizedStringKey(key))
                }

                ForEach(summary.activities) { activity in
                    if remainingDays(until: activity.expire, now: context.date) > 0 {
                        Text(
                            "「\(activity.name)」剩余 \(remainingDays(until: activity.expire, now: context.date)) 天")
                    } else {
                        Text("「\(activity.name)」剩余不到 1 天")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
    }

    private func remainingDays(until expire: Date, now: Date) -> Int {
        max(0, Int(expire.timeIntervalSince(now) / 86_400))
    }
}

struct TodayStageTipView_Previews: PreviewProvider {
    static var previews: some View {
        TodayStageTipView()
            .environmentObject(MAAViewModel())
            .frame(width: 260)
    }
}
