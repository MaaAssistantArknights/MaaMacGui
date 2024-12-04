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
            ForEach($viewModel.tasks, id: \.id) { $task in
                switch task.task {
                case .startup(let config):
                    TaskCell(id: task.id, config: config, enabled: $task.enabled)
                case .closedown(let config):
                    TaskCell(id: task.id, config: config, enabled: $task.enabled)
                case .recruit(let config):
                    TaskCell(id: task.id, config: config, enabled: $task.enabled)
                case .infrast(let config):
                    TaskCell(id: task.id, config: config, enabled: $task.enabled)
                case .fight(let config):
                    TaskCell(id: task.id, config: config, enabled: $task.enabled)
                case .mall(let config):
                    TaskCell(id: task.id, config: config, enabled: $task.enabled)
                case .award(let config):
                    TaskCell(id: task.id, config: config, enabled: $task.enabled)
                case .roguelike(let config):
                    TaskCell(id: task.id, config: config, enabled: $task.enabled)
                case .reclamation(let config):
                    TaskCell(id: task.id, config: config, enabled: $task.enabled)
                }
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
            viewModel.dailyTasksDetailMode = .log
            await viewModel.tryStartTasks()
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
        if index >= viewModel.tasks.count {
            self.selection = viewModel.tasks.last?.id
        } else {
            self.selection = viewModel.tasks[index].id
        }
    }

    private func moveTask(from: IndexSet, to: Int) {
        viewModel.tasks.move(fromOffsets: from, toOffset: to)
    }

    private func deselectTask(_ viewMode: MAAViewModel.DailyTasksDetailMode) {
        if viewMode != .taskConfig {
            selection = nil
        }
    }

    private func selectLastTask(_ shouldSelect: Bool) {
        if shouldSelect {
            selection = viewModel.tasks.last?.id
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
