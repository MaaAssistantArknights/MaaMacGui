import SwiftUI

struct TaskTimerView: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    @State private var showingAlertForPreventingSleep = false
    @ObservedObject private var timerManager = TaskTimerManager.shared

    var body: some View {
        HStack {
            Button(action: {
                viewModel.appendNewTaskTimer()
            }) {
                Label("新增定时", systemImage: "plus")
            }
            .padding()
            Spacer()
        }
        Text("定时按本机时区执行；运行中默认跳过。强制开始会等待日常任务停止和清理，工具任务仍跳过。")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
        if let failure = timerManager.failure {
            Text(failure).foregroundStyle(.red).padding(.horizontal)
        }
        List {
            ForEach($viewModel.scheduledDailyTaskTimers.indices, id: \.self) { index in
                TaskTimerItem(
                    taskTimer: $viewModel.scheduledDailyTaskTimers[index],
                    onDelete: {
                        viewModel.scheduledDailyTaskTimers.remove(at: index)
                    },
                    onEnabled: showAlertIfNeeded
                )
            }
        }
        if !timerManager.recentOccurrences.isEmpty {
            DisclosureGroup("最近定时结果") {
                ForEach(timerManager.recentOccurrences) { occurrence in
                    HStack {
                        Text(occurrence.scheduledAt, style: .date)
                        Text(occurrence.scheduledAt, style: .time)
                        Spacer()
                        Text(occurrence.result.displayName)
                    }
                    .help(occurrence.detail)
                }
            }
            .padding()
        }
        Button("取消等待中的定时启动") { timerManager.cancelPendingStart() }
            .padding(.horizontal)
        .alert("允许阻止系统睡眠",
               isPresented: $showingAlertForPreventingSleep,
               actions: {
                   Button("允许") {
                       viewModel.preventSystemSleeping = true
                   }
                   Button("取消", role: .cancel) {}
               }, message: {
                   Text("日常任务定时执行会在系统休眠之后失效, 打开此功能可以阻止系统自动睡眠")
               })
    }

    private func showAlertIfNeeded() {
        guard !viewModel.preventSystemSleeping else { return }
        showingAlertForPreventingSleep = true
    }
}

struct TaskTimerItem: View {
    @Binding var taskTimer: MAAViewModel.DailyTaskTimer
    var onDelete: () -> Void
    var onEnabled: () -> Void

    let hours = Array(0...23)
    let minutes = Array(0...59)

    var body: some View {
        HStack {
            Button(action: {
                onDelete()
            }, label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.red)
            })
            .buttonStyle(PlainButtonStyle())

            Spacer()

            Picker(selection: $taskTimer.hour, label: Text("时")) {
                ForEach(hours, id: \.self) { hour in
                    Text("\(hour)")
                }
            }
            .frame(width: 90)

            Picker(selection: $taskTimer.minute, label: Text("分")) {
                ForEach(minutes, id: \.self) { minute in
                    Text(String(format: "%02d", minute))
                }
            }
            .frame(width: 90)

            Toggle("强制开始", isOn: $taskTimer.forceStart)
                .fixedSize()
                .help("仅停止本应用的日常任务；等待停止和后置清理完成后开始，最多等待 30 秒。")

            Toggle(isOn: $taskTimer.isEnabled, label: {
                Text("开启")
            })
            .toggleStyle(.switch)
            .onChange(of: taskTimer.isEnabled) {
                if $1 {
                    onEnabled()
                }
            }

            Spacer()
        }
        .padding()
    }
}

struct TaskTimerView_Previews: PreviewProvider {
    static var previews: some View {
        TaskTimerView()
            .environmentObject(MAAViewModel())
    }
}

private extension ScheduleOccurrence.Result {
    var displayName: String {
        switch self {
        case .pending: String(localized: "等待交接")
        case .started: String(localized: "已开始")
        case .completed: String(localized: "已完成")
        case .skipped: String(localized: "已跳过")
        case .failed: String(localized: "失败")
        case .cancelled: String(localized: "已取消")
        case .missed: String(localized: "已错过")
        case .interrupted: String(localized: "上次结果未知")
        }
    }
}
