//
//  LogView.swift
//  MAA
//
//  Created by hguandl on 16/4/2023.
//

import SwiftUI

/// 日志视图：支持「精简」（时间+信息表格）与「详细」（卡片分组日志）两种样式，
/// 对齐 Windows 版 `TaskQueueView` 的 plain-text 与 card-log 两种渲染。
struct LogView: View {
    @EnvironmentObject private var viewModel: MAAViewModel

    var body: some View {
        ScrollViewReader { proxy in
            Group {
                if viewModel.useCardLog {
                    CardLogView(proxy: proxy)
                } else {
                    ConciseLogView(proxy: proxy)
                }
            }
            .animation(.default, value: viewModel.logs)
            .animation(.default, value: viewModel.logCards)
            .toolbar {
                Toggle(isOn: $viewModel.trackTail) {
                    Label("现在", systemImage: "arrow.down.to.line")
                }
                .help("自动滚动到底部")
            }
        }
    }
}

// MARK: - 精简模式

private struct ConciseLogView: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    let proxy: ScrollViewProxy

    var body: some View {
        Table(viewModel.logs) {
            TableColumn("时间", value: \.date.maaGuiLogFormat)
                .width(min: 100, ideal: 125, max: 150)
            TableColumn("信息") { log in
                Text(log.content)
                    .textSelection(.enabled)
                    .foregroundStyle(log.color.textColor)
                    .fontWeight(log.weight?.fontWeight ?? .regular)
                    .help(log.toolTip ?? "")
                    .lineLimit(nil)
            }
            .width(min: 100, ideal: 300)
        }
        .onChange(of: viewModel.logs) {
            if viewModel.trackTail {
                withAnimation {
                    proxy.scrollTo(viewModel.logs.last?.id ?? UUID())
                }
            }
        }
    }
}

// MARK: - 详细模式（卡片日志）

private struct CardLogView: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    let proxy: ScrollViewProxy

    private var visibleCards: [LogCardItem] {
        viewModel.logCards.filter { !$0.items.isEmpty || $0.isDivider }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(visibleCards) { card in
                    if card.isDivider {
                        LogCardDivider(header: card.header)
                            .id(card.id)
                    } else {
                        LogCardRow(card: card)
                            .id(card.id)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .onChange(of: viewModel.logCards) {
            if viewModel.trackTail, let last = visibleCards.last {
                withAnimation {
                    proxy.scrollTo(last.id)
                }
            }
        }
        .onChange(of: viewModel.trackTail) {
            if $1, let last = visibleCards.last {
                withAnimation {
                    proxy.scrollTo(last.id)
                }
            }
        }
    }
}

/// 一张日志卡片：左侧时间轴（起止时间 + 可选缩略图），右侧分组日志。
private struct LogCardRow: View {
    let card: LogCardItem

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // 左侧时间轴列
            VStack(alignment: .leading, spacing: 4) {
                if let start = card.startTime {
                    Text(start.maaGuiLogFormat)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let thumbnail = card.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 120, maxHeight: 90)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .shadow(radius: 1)
                        .help("截图")
                }

                if let end = card.endTime, (end != card.startTime || card.items.count > 1) {
                    Text(end.maaGuiLogFormat)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 110, alignment: .leading)

            // 右侧日志内容列
            VStack(alignment: .leading, spacing: 3) {
                ForEach(card.items) { log in
                    Text(log.content)
                        .fontWeight(log.weight?.fontWeight ?? .regular)
                        .foregroundStyle(log.color.textColor)
                        .textSelection(.enabled)
                        .help(log.toolTip ?? "")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .quaternarySystemFill))
        )
    }
}

/// 卡片之间的分隔标题（对应 Windows hc:Divider）。
private struct LogCardDivider: View {
    let header: String?

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(.quaternary).frame(height: 1)
            if let header {
                Text(header)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Rectangle().fill(.quaternary).frame(height: 1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

struct LogView_Previews: PreviewProvider {
    static var previews: some View {
        LogView().environmentObject(MAAViewModel())
    }
}
