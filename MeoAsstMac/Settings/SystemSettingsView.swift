import ServiceManagement
import SwiftUI

struct SystemSettingsView: View {
    @EnvironmentObject private var viewModel: MAAViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LoginItemSettingsView()

            Divider()
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
    }
}

struct SystemSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SystemSettingsView()
            .environmentObject(MAAViewModel())
    }
}

@MainActor struct LoginItemSettingsView: View {
    @StateObject private var service: LoginItemService
    @Environment(\.scenePhase) private var scenePhase

    init(service: LoginItemService? = nil) {
        _service = StateObject(wrappedValue: service ?? LoginItemService())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(
                "登录时启动 MAA",
                isOn: Binding(
                    get: { service.status == .enabled },
                    set: { enabled in Task { await service.setEnabled(enabled) } }
                )
            )
            .disabled(service.hasPendingOperation)

            Text("登录后仅打开应用，不会自动开始日常任务")
                .font(.caption).foregroundStyle(.secondary)
            statusText.font(.caption).foregroundStyle(.secondary)

            if let error = service.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
                Button("重试") { Task { await service.retry() } }
                    .disabled(service.isUpdating)
            }

            VStack(alignment: .leading) {
                Button("打开系统登录项设置") { service.openSettings() }
                if service.status == .requiresApproval {
                    Button("取消登录项申请") {
                        Task { await service.setEnabled(false) }
                    }
                    .disabled(service.hasPendingOperation)
                }
            }
        }
        .onAppear { service.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { service.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            service.refresh()
        }
    }

    private var statusText: Text {
        switch service.status {
        case .notRegistered: Text("登录项未启用")
        case .enabled: Text("登录项已启用")
        case .requiresApproval: Text("等待系统批准，请在系统设置中允许登录时启动")
        case .notFound: Text("找不到登录服务，请将应用移至固定位置后重试")
        @unknown default: Text("无法确认登录项状态，请检查系统设置")
        }
    }
}

#if DEBUG
@MainActor private struct PreviewLoginItem: LoginItemManaging {
    let status: SMAppService.Status
    func register() async throws {}
    func unregister() async throws {}
    func openSettings() {}
}

#Preview("Login item states") {
    VStack(alignment: .leading, spacing: 20) {
        ForEach([SMAppService.Status.notRegistered, .enabled, .requiresApproval, .notFound], id: \.rawValue) {
            LoginItemSettingsView(service: LoginItemService(manager: PreviewLoginItem(status: $0)))
        }
    }.padding().frame(width: 440)
}
#endif
