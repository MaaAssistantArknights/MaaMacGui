import SwiftUI

struct SystemSettingsView: View {
    @EnvironmentObject private var viewModel: MAAViewModel

    @State private var showHotkeys = false

    var body: some View {
        VStack(alignment: .leading) {
            Button("全局热键…") { showHotkeys = true }

            Toggle(isOn: $viewModel.preventSystemSleeping) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("阻止系统睡眠")
                    Text("日常任务定时执行会在系统休眠之后失效, 打开此功能可以阻止系统自动睡眠")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: $viewModel.useWebGPU) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("使用WebGPU（实验功能）")
                    Text("修改后需重启MAA以生效")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .sheet(isPresented: $showHotkeys) {
            HotkeySettingsView(service: viewModel.globalHotkeys)
        }
    }
}

struct SystemSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SystemSettingsView()
            .environmentObject(MAAViewModel())
    }
}
