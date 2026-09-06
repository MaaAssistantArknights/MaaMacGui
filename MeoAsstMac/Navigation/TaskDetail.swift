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
                if let id, let task = viewModel.tasks[id] {
                    switch task {
                    case .startup(let config):
                        StartupSettingsView(config: taskConfigBinding(config, id: id))
                    case .recruit(let config):
                        RecruitSettingsView(config: taskConfigBinding(config, id: id))
                    case .infrast(let config):
                        InfrastSettingsView(config: taskConfigBinding(config, id: id))
                    case .fight(let config):
                        FightSettingsView(config: taskConfigBinding(config, id: id))
                    case .depotMaintain(let config):
                        DepotMaintainSettingsView(config: taskConfigBinding(config, id: id))
                    case .mall(let config):
                        MallSettingsView(config: taskConfigBinding(config, id: id))
                    case .award(let config):
                        AwardSettingsView(config: taskConfigBinding(config, id: id))
                    case .roguelike(let config):
                        RoguelikeSettingsView(config: taskConfigBinding(config, id: id))
                    case .reclamation(let config):
                        ReclamationSettingsView(config: taskConfigBinding(config, id: id))
                    case .closedown(_):
                        EmptyView()
                    }
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

    private func taskConfigBinding<T: MAATaskConfiguration>(_ value: T, id: UUID) -> Binding<T> {
        Binding {
            value
        } set: {
            viewModel.tasks[id] = $0.projectedTask
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder private func detailToolbar() -> some ToolbarContent {
        ToolbarItemGroup {
            Menu {
                ForEach(defaultTaskConfigurations, id: \.type) { config in
                    Button(config.title) {
                        addTask(config: config)
                    }
                }
            } label: {
                Label("添加", systemImage: "plus")
            }
            .help("添加任务")
        }

        ToolbarItem {
            ControlGroup {
                ViewDetaiTabButton(mode: .taskConfig, selection: $viewModel.dailyTasksDetailMode) {
                    Label("选项", systemImage: "gearshape")
                }
                ViewDetaiTabButton(mode: .log, selection: $viewModel.dailyTasksDetailMode) {
                    Label("日志", systemImage: "note.text")
                }
                ViewDetaiTabButton(mode: .timerConfig, selection: $viewModel.dailyTasksDetailMode) {
                    Label("定时", systemImage: "clock.arrow.2.circlepath")
                }
            } label: {
                Label("内容", systemImage: "menucard")
            }
        }
    }

    // MARK: - Actions

    private func addTask<T: MAATaskConfiguration>(config: T) {
        viewModel.tasks.append(config: config)
        viewModel.newTaskAdded = true
    }
}

struct ViewDetaiTabButton<L: View>: View {
    let mode: MAAViewModel.DailyTasksDetailMode
    @Binding var selection: MAAViewModel.DailyTasksDetailMode
    let label: L

    init(
        mode: MAAViewModel.DailyTasksDetailMode, selection: Binding<MAAViewModel.DailyTasksDetailMode>,
        @ViewBuilder label: () -> L
    ) {
        self.mode = mode
        self._selection = selection.animation(.default)
        self.label = label()
    }

    var body: some View {
        Button {
            selection = mode
        } label: {
            label
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
