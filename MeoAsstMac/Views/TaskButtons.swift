//
//  TaskButtons.swift
//  MAA
//
//  Created by hguandl on 30/4/2023.
//

import SwiftUI

struct TaskButtons: View {
    @EnvironmentObject var viewModel: MAAViewModel

    var body: some View {
        Button("开始任务") {
            Task {
                viewModel.dailyTasksDetailMode = .log
                await viewModel.tryStartTasks()
            }
        }
        .keyboardShortcut("R", modifiers: .command)

        Button("停止任务") {
            Task {
                try await viewModel.stop()
            }
        }
        .keyboardShortcut(".", modifiers: .command)

        Button("全部启用") {
            for (index, task) in viewModel.tasks.enumerated() {
                switch task.task {
                case .roguelike, .reclamation:
                    continue
                default:
                    viewModel.tasks[index].enabled = true
                }
            }
        }
        .keyboardShortcut("E", modifiers: [.command, .shift])

        Button("全部取消") {
            for (index, _) in viewModel.tasks.enumerated() {
                viewModel.tasks[index].enabled = false
            }
        }
        .keyboardShortcut("D", modifiers: [.command, .shift])
    }
}

struct TaskButtons_Previews: PreviewProvider {
    static var previews: some View {
        TaskButtons().environmentObject(MAAViewModel())
    }
}
