import SwiftUI

struct SystemSettingsView: View {
    @EnvironmentObject private var viewModel: MAAViewModel

    var body: some View {
        VStack(alignment: .leading) {
            Toggle(isOn: $viewModel.preventSystemSleeping) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("阻止系统睡眠", comment: ""))
                    Text("日常任务定时执行会在系统休眠之后失效, 打开此功能可以阻止系统自动睡眠")
                        .font(.caption).foregroundColor(.secondary)
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
