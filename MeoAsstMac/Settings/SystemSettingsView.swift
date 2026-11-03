import SwiftUI

struct SystemSettingsView: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    @AppStorage(MenuBarKeeper.enabledKey) private var keepInMenuBar = false

    var body: some View {
        VStack(alignment: .leading) {
            Toggle(isOn: $viewModel.preventSystemSleeping) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("阻止系统睡眠")
                    Text("日常任务定时执行会在系统休眠之后失效, 打开此功能可以阻止系统自动睡眠")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: $keepInMenuBar) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("关闭窗口时常驻菜单栏")
                    Text("关闭主窗口后 MAA 将隐藏到菜单栏并继续运行，不在程序坞中显示。可通过菜单栏图标重新打开或退出")
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
