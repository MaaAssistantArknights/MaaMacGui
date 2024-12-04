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
                        .foregroundColor(.secondary)
                }
                .lineLimit(1)
            }
            Spacer()
            TaskIndicator(id: id)
        }
        .padding(.vertical, 6)
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
            Image(systemName: "slash.circle").foregroundColor(.secondary)
        case .failure:
            Image(systemName: "xmark.circle").foregroundColor(.red)
        case .running:
            ProgressView().controlSize(.small)
        case .success:
            Image(systemName: "checkmark.circle").foregroundColor(.green)
        case .none:
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
