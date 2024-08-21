//
//  TaskButtons.swift
//  MAA
//
//  Created by hguandl on 30/4/2023.
//

import SwiftUI

struct TaskButtons: View {
    @ObservedObject var viewModel: MAAViewModel

    var body: some View {
        Button("开始任务") {
            Task {
                viewModel.dailyTasksDetailMode = .log
                try await viewModel.startTasks()
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
            for id in viewModel.tasks.keys {
                switch viewModel.tasks[id]?.typeName {
                case .Roguelike, .Reclamation:
                    continue
                default:
                    viewModel.tasks[id]?.enabled = true
                }
            }
        }
        .keyboardShortcut("E", modifiers: [.command, .shift])

        Button("全部取消") {
            for id in viewModel.tasks.keys {
                viewModel.tasks[id]?.enabled = false
            }
        }
        .keyboardShortcut("D", modifiers: [.command, .shift])
    }
}

struct TaskButtons_Previews: PreviewProvider {
    static var previews: some View {
        TaskButtons(viewModel: MAAViewModel())
    }
}
