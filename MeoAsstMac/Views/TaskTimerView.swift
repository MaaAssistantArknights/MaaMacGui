import SwiftUI

struct TaskTimerView: View {
    @EnvironmentObject private var viewModel: MAAViewModel

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
        List {
            ForEach($viewModel.scheduledDailyTaskTimers.indices, id: \.self) { index in
                TaskTimerItem(taskTimer: $viewModel.scheduledDailyTaskTimers[index]) {
                    viewModel.scheduledDailyTaskTimers.remove(at: index)
                }
            }
        }
    }
}

struct TaskTimerItem: View {
    @Binding var taskTimer: MAAViewModel.DailyTaskTimer
    var onDelete: (() -> Void)

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

            Picker(selection: $taskTimer.hour, label: Text("时")) {
                ForEach(hours, id: \.self) { hour in
                    Text("\(hour)")
                }
            }
            .frame(width: 100)

            Picker(selection: $taskTimer.minute, label: Text("分")) {
                ForEach(minutes, id: \.self) { minute in
                    Text(String(format: "%02d", minute))
                }
            }
            .frame(width: 100)

            Spacer()

            Toggle(isOn: $taskTimer.isEnabled, label: {
                Text("开启")
            })
            .toggleStyle(.switch)
            
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
