import SwiftUI

struct SystemSettingsView: View {
    @EnvironmentObject private var viewModel: MAAViewModel

    var body: some View {
        VStack(alignment: .leading) {
            Toggle(isOn: $viewModel.preventSystemSleeping) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("阻止系统睡眠")
                    Text("日常任务定时执行会在系统休眠之后失效, 打开此功能可以阻止系统自动睡眠")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: $viewModel.useNotification) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("任务通知提醒")
                    Text("任务完成、出错或掉线时发送系统通知提醒；任务全部完成时额外预约理智恢复提醒")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
}

struct SystemSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SystemSettingsView()
            .environmentObject(MAAViewModel())
    }
}
