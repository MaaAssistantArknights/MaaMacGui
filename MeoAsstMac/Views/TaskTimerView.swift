import SwiftUI

struct TaskTimerView: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    @State private var showingAlertForPreventingSleep = false

    var body: some View {
        HStack {
            Button(action: {
                viewModel.appendNewTaskTimer()
            }) {
                Label(NSLocalizedString("新增定时", comment: ""), systemImage: "plus")
            }
            .padding()
            Spacer()
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
        .alert(NSLocalizedString("允许阻止系统睡眠", comment: ""),
               isPresented: $showingAlertForPreventingSleep,
               actions: {
                   Button(NSLocalizedString("允许", comment: "")) {
                       viewModel.preventSystemSleeping = true
                   }
                   Button(NSLocalizedString("取消", comment: ""), role: .cancel) {}
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
                    .foregroundColor(.red)
            })
            .buttonStyle(PlainButtonStyle())

            Spacer()

            Picker(selection: $taskTimer.hour, label: Text(NSLocalizedString("时", comment: ""))) {
                ForEach(hours, id: \.self) { hour in
                    Text("\(hour)")
                }
            }
            .frame(width: 100)

            Picker(selection: $taskTimer.minute, label: Text(NSLocalizedString("分", comment: ""))) {
                ForEach(minutes, id: \.self) { minute in
                    Text(String(format: "%02d", minute))
                }
            }
            .frame(width: 100)

            Spacer()

            Toggle(isOn: $taskTimer.isEnabled, label: {
                Text(NSLocalizedString("开启", comment: ""))
            })
            .toggleStyle(.switch)
            .onChange(of: taskTimer.isEnabled) {
                if $0 {
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
