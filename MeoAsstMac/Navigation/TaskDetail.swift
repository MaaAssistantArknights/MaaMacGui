//
//  TaskDetail.swift
//  MAA
//
//  Created by hguandl on 19/4/2023.
//

import SwiftUI

struct TaskDetail: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    let id: UUID?

    var body: some View {
        VStack {
            switch viewModel.dailyTasksDetailMode {
            case .taskConfig:
                if let id {
                    viewModel.taskConfigView(id: id)
                } else {
                    Text("Please select one task to config")
                }
            case .log:
                LogView()
            case .timerConfig:
                TaskTimerView()
            }
        }
        .padding()
        .toolbar(content: detailToolbar)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder private func detailToolbar() -> some ToolbarContent {
        ToolbarItemGroup {
            Menu {
                ForEach(MAATask.TypeName.daily, id: \.self) { name in
                    Button(name.description) {
                        addTask(MAATask(type: name))
                    }
                }
            } label: {
                Label(NSLocalizedString("添加", comment: ""), systemImage: "plus")
            }
            .help(NSLocalizedString("添加任务", comment: ""))
        }

        ToolbarItemGroup {
            HStack {
                Divider()

                ViewDetaiTabButton(mode: .taskConfig, icon: "gearshape", selection: $viewModel.dailyTasksDetailMode)
                ViewDetaiTabButton(mode: .log, icon: "note.text", selection: $viewModel.dailyTasksDetailMode)
                ViewDetaiTabButton(mode: .timerConfig, icon: "clock.arrow.2.circlepath", selection: $viewModel.dailyTasksDetailMode)
            }
        }
    }

    // MARK: - Actions

    private func addTask(_ task: MAATask) {
        viewModel.tasks.append(task)
        viewModel.newTaskAdded = true
    }
}

struct ViewDetaiTabButton: View {
    let mode: MAAViewModel.DailyTasksDetailMode
    let icon: String
    @Binding var selection: MAAViewModel.DailyTasksDetailMode

    var body: some View {
        Button {
            selection = mode
        } label: {
            Image(systemName: icon)
                .foregroundColor(mode == selection ? Color.accentColor : nil)
        }
    }
}

struct TaskDetail_Previews: PreviewProvider {
    static var previews: some View {
        TaskDetail(id: nil)
            .environmentObject(MAAViewModel())
    }
}
