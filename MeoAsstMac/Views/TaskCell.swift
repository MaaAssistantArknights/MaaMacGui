//
//  TaskCell.swift
//  MAA
//
//  Created by hguandl on 14/4/2023.
//

import SwiftUI

struct TaskCell<Config: MAATaskConfiguration>: View {
    let id: UUID
    let config: Config

    @Binding var enabled: Bool
    @EnvironmentObject private var viewModel: MAAViewModel

    /// 状态背景色（对齐 Windows Dark.xaml 的 12.5% 透明度刷子）
    private var statusColor: Color? {
        switch viewModel.taskStatus[id] {
        case .running:
            Color(hex: 0x20326CF3)
        case .success:
            Color(hex: 0x2090EE90)
        case .failure:
            Color(hex: 0x20FF4444)
        default:
            nil
        }
    }

    /// 禁用的任务：整行半透明（对齐 Windows Skipped）
    private var isSkipped: Bool {
        viewModel.taskStatus[id] == .skipped
    }

    var body: some View {
        HStack {
            Toggle("", isOn: $enabled)
            VStack(alignment: .leading, spacing: 4) {
                Text(config.title)
                    .font(.headline)

                HStack {
                    Text(config.subtitle)
                        .font(.subheadline)

                    Text(config.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
            }
            Spacer()
            TaskIndicator(id: id)
        }
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(statusColor ?? Color.clear)
        )
        .opacity(isSkipped ? 0.5 : 1)
        .contextMenu {
            TaskButtons()
        }
    }
}

private struct TaskIndicator: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    let id: UUID

    var body: some View {
        switch viewModel.taskStatus[id] {
        case .cancel:
            Image(systemName: "slash.circle").foregroundStyle(.secondary)
        case .failure:
            Image(systemName: "xmark.circle").foregroundStyle(.red)
        case .running:
            ProgressView().controlSize(.small)
        case .success:
            Image(systemName: "checkmark.circle").foregroundStyle(.green)
        case .idle, .skipped, .none:
            EmptyView()
        }
    }
}

struct MAATaskCell_Previews: PreviewProvider {
    static var previews: some View {
        TaskCell(id: UUID(), config: StartupConfiguration(), enabled: .constant(true))
            .environmentObject(MAAViewModel())
    }
}
