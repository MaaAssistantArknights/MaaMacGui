import SwiftUI

struct SystemSettingsView: View {
    @EnvironmentObject private var viewModel: MAAViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("日志样式", selection: $viewModel.useCardLog) {
                Text("精简").tag(false)
                Text("详细").tag(true)
            }
            .pickerStyle(.segmented)

            Text("详细：以卡片分组展示日志，包含掉落截图缩略图；精简：以表格逐行展示")
                .font(.caption).foregroundStyle(.secondary)

            Divider()

            Toggle(isOn: $viewModel.preventSystemSleeping) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("阻止系统睡眠")
                    Text("日常任务定时执行会在系统休眠之后失效, 打开此功能可以阻止系统自动睡眠")
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
