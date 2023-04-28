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
        .toolbar(content: listToolbar)
        .animation(.default, value: viewModel.tasks)
        .onReceive(viewModel.$showLog, perform: deselectTask)
        .onReceive(viewModel.$newTaskAdded, perform: selectLastTask)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder private func listToolbar() -> some ToolbarContent {
        ToolbarItemGroup {
            Button(action: deleteSelectedTask) {
                Label("删除", systemImage: "trash")
            }
            .help("删除任务")
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
                    Label("停止", systemImage: "stop.fill")
                }
                .help("停止")
            case .idle:
                Button(action: start) {
                    Label("开始", systemImage: "play.fill")
                }
                .help("开始")
            }
        }
    }

    // MARK: - Actions

    private func start() {
        Task {
            deselectTask(true)
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

    private func deselectTask(_ shouldDeselect: Bool) {
        if shouldDeselect {
            selection = nil
        }
    }

    private func selectLastTask(_ shouldSelect: Bool) {
        if shouldSelect {
            selection = viewModel.tasks.keys.last
        }
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
