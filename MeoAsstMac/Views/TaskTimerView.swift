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
                    .help(occurrence.explanation)
                    .accessibilityHint(occurrence.explanation)
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

private extension ScheduleOccurrence {
    var explanation: String {
        switch detail {
        case "utilityTaskBusy": String(localized: "工具任务正在运行，本次已跳过。")
        case "dailyTaskBusy": String(localized: "日常任务正在运行，本次已跳过。")
        case "anotherSchedulePending": String(localized: "另一条定时计划正在等待交接。")
        case "handoffTimedOut": String(localized: "等待停止或清理超过 30 秒，本次不再开始。")
        case "cleanupFailed": String(localized: "后置清理未成功，本次不再开始。")
        case "stopFailed": String(localized: "停止当前任务失败，本次不再开始。")
        case "startFailed": String(localized: "任务启动失败，请检查连接与配置。")
        case "admissionRejected": String(localized: "任务入口正忙，本次已跳过。")
        case "runChanged": String(localized: "等待期间已开始其他运行，定时交接已取消。")
        case "scheduleChanged": String(localized: "计划已修改或停用，定时交接已取消。")
        case "userCancelled": String(localized: "用户已取消本次定时启动。")
        case "simultaneousSchedule": String(localized: "同一批到期计划只执行一条，本次已跳过。")
        case "nonexistentLocalTime": String(localized: "夏令时跳过了此本地时间。")
        case "triggerExpired": String(localized: "已超出本次定时触发窗口。")
        case "previousRunOutcomeUnknown": String(localized: "上次应用退出前的任务结果未知，不会自动重跑。")
        default: ""
        }
    }
}
