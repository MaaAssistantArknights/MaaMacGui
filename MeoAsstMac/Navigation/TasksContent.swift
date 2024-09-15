//
//  TasksContent.swift
//  MAA
//
//  Created by hguandl on 14/4/2023.
//

import SwiftUI

struct TasksContent: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    @Binding var selection: UUID?

    var body: some View {
        List(selection: $selection) {
            ForEach(viewModel.tasks.keys, id: \.self) { id in
                TaskCell(id: id)
            }
            .onMove(perform: moveTask)
        }
        .onChange(of: selection, perform: updateViewMode)
        .toolbar(content: listToolbar)
        .animation(.default, value: viewModel.tasks)
        .onReceive(viewModel.$newTaskAdded, perform: selectLastTask)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder private func listToolbar() -> some ToolbarContent {
        ToolbarItemGroup {
            Button(action: deleteSelectedTask) {
                Label(NSLocalizedString("删除", comment: ""), systemImage: "trash")
            }
            .help(NSLocalizedString("删除任务", comment: ""))
            .disabled(shouldDisableDeletion)
        }

        ToolbarItemGroup {
            switch viewModel.status {
            case .pending:
                Button(action: {}) {
                    ProgressView().controlSize(.small)
                }
                .disabled(true)
            case .busy:
                Button(action: stop) {
                    Label(NSLocalizedString(NSLocalizedString("停止", comment: ""), comment: ""), systemImage: "stop.fill")
                }
                .help(NSLocalizedString(NSLocalizedString("停止", comment: ""), comment: ""))
            case .idle:
                Button(action: start) {
                    Label(NSLocalizedString(NSLocalizedString("开始", comment: ""), comment: ""), systemImage: "play.fill")
                }
                .help(NSLocalizedString(NSLocalizedString("开始", comment: ""), comment: ""))
            }
        }
    }

    // MARK: - Actions

    private func start() {
        Task {
            viewModel.dailyTasksDetailMode = .log
            try await viewModel.startTasks()
        }
    }

    private func stop() {
        Task {
            try await viewModel.stop()
        }
    }

    private func deleteSelectedTask() {
        guard viewModel.tasks.count > 1,
              let selection,
              let index = viewModel.tasks.firstIndex(id: selection)
        else {
            return
        }
        viewModel.tasks.remove(id: selection)
        if index >= viewModel.tasks.keys.count {
            self.selection = viewModel.tasks.keys.last
        } else {
            self.selection = viewModel.tasks.keys[index]
        }
    }

    private func moveTask(from: IndexSet, to: Int) {
        viewModel.tasks.keys.move(fromOffsets: from, toOffset: to)
    }

    private func deselectTask(_ viewMode: MAAViewModel.DailyTasksDetailMode) {
        if viewMode != .taskConfig {
            selection = nil
        }
    }

    private func selectLastTask(_ shouldSelect: Bool) {
        if shouldSelect {
            selection = viewModel.tasks.keys.last
        }
    }

    private func updateViewMode(_ selectedTaskID: UUID?) {
        guard selectedTaskID != nil else { return }
        viewModel.dailyTasksDetailMode = .taskConfig
    }

    // MARK: - State Wrappers

    private var shouldDisableDeletion: Bool {
        if let selection, case .startup = viewModel.tasks[selection] {
            return true
        } else {
            return selection == nil
        }
    }
}

struct TasksContent_Previews: PreviewProvider {
    static var previews: some View {
        TasksContent(selection: .constant(nil))
            .environmentObject(MAAViewModel())
    }
}
