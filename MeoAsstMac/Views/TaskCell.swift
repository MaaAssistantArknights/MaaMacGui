//
//  TaskCell.swift
//  MAA
//
//  Created by hguandl on 14/4/2023.
//

import SwiftUI

struct TaskCell: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    let id: UUID

    var body: some View {
        HStack {
            Toggle("", isOn: enabled)
            VStack(alignment: .leading, spacing: 4) {
                Text(overview.title)
                    .font(.headline)

                HStack {
                    Text(overview.subtitle)
                        .font(.subheadline)

                    Text(overview.summary)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .lineLimit(1)
            }
            Spacer()
            indicator
        }
        .padding(.vertical, 6)
        .animation(.default, value: viewModel.taskStatus[id])
    }

    @ViewBuilder private var indicator: some View {
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

    private var enabled: Binding<Bool> {
        Binding {
            viewModel.tasks[id]?.enabled ?? false
        } set: { newValue in
            viewModel.tasks[id]?.enabled = newValue
        }
    }

    private var overview: MAATask.Overview {
        viewModel.tasks[id]?.overview ?? ("", "", "")
    }
}

struct MAATaskCell_Previews: PreviewProvider {
    static var viewModel = MAAViewModel()
    static var previews: some View {
        TaskCell(id: UUID())
            .environmentObject(viewModel)
    }
}
