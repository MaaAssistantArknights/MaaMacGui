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
            if let id {
                viewModel.taskConfigView(id: id)
            } else {
                LogView()
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
                Label("添加", systemImage: "plus")
            }
            .help("添加任务")
        }

        ToolbarItemGroup {
            Button {
                viewModel.showLog = true
            } label: {
                Label("日志", systemImage: "note.text")
            }
            .help("运行日志")
        }
    }

    // MARK: - Actions

    private func addTask(_ task: MAATask) {
        viewModel.tasks.append(task)
        viewModel.newTaskAdded = true
    }
}

struct TaskDetail_Previews: PreviewProvider {
    static var previews: some View {
        TaskDetail(id: nil)
    }
}
