import ServiceManagement
import SwiftUI

struct BackgroundScheduleSettingsView: View {
    @ObservedObject private var service = BackgroundScheduleService.shared

    var body: some View {
        GroupBox("退出后定时启动") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("启用退出后定时启动", isOn: Binding(get: { service.enabled }, set: { service.setEnabled($0) }))
                    .disabled(!service.available && !service.enabled)
                Text("仅已登录会话；约 0–60 秒后唤起应用，另计初始化时间。唤醒后仅补跑 5 分钟内的计划，关机或未登录时不执行。")
                    .font(.caption).foregroundStyle(.secondary)
                Text(statusText).font(.caption)
                if let failure = service.failure { Text(failure).font(.caption).foregroundStyle(.red) }
                HStack {
                    Button("刷新系统状态") { service.refreshStatus() }
                    Button("打开登录项设置") { service.openSystemSettings() }
                    if service.enabled { Button("修复后台定时注册") { service.setEnabled(true) }.disabled(!service.available) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusText: String {
        switch service.status {
        case .enabled: String(localized: "系统状态：已启用")
        case .requiresApproval: String(localized: "系统状态：等待批准")
        case .notRegistered: String(localized: "系统状态：未注册")
        case .notFound: String(localized: "系统状态：找不到调度程序")
        @unknown default: String(localized: "系统状态：未知")
        }
    }
}
