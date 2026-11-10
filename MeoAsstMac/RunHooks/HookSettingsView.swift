import SwiftUI
import UniformTypeIdentifiers

struct HookSettingsView: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    @ObservedObject var store: HookSettingsStore
    @State private var selectingBefore = true
    @State private var selecting = false
    @State private var error: String?

    var body: some View {
        Form {
            Toggle("启用日常任务脚本", isOn: $store.configuration.enabled)
            Text("仅作用于日常队列。前置脚本在连接前执行，后置脚本在完成、失败或取消后清理。脚本可修改设备设置，请仅选择可信的本地文件。")
                .font(.caption).foregroundStyle(.secondary)
            commandEditor(before: true)
            commandEditor(before: false)
            Stepper(value: $store.configuration.timeoutSeconds, in: 1...300) {
                Text("脚本超时（秒）") + Text(": \(store.configuration.timeoutSeconds)")
            }
            Text("工作目录：应用支持目录中的 RunHooks。每行一个参数，原样传递；环境提供 MAA_RUN_ID、MAA_PROFILE_ID、MAA_RUN_ORIGIN、MAA_RUN_RESULT 和 MAA_ADB_PATH。")
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Text("脚本以 /bin/zsh -f 运行，不加载 ~/.zshrc 等用户 shell 配置；PATH 固定为 /usr/bin:/bin:/usr/sbin:/sbin，Homebrew 等第三方工具请使用绝对路径。")
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            if let previous = viewModel.dailyRunCoordinator.lastTerminal,
               previous.outcome == .interrupted || previous.cleanupSucceeded == false,
               previous.cleanupSucceeded != true {
                Text("上次运行中断，无法确认后置清理是否完成。请检查设备设置；不会自动重放脚本。")
                    .foregroundStyle(.orange)
                if store.configuration.after != nil {
                    Button("运行后置恢复（会实际执行）") { Task { await viewModel.recoverInterruptedRun() } }
                        .disabled(!viewModel.canStartTasks)
                }
            }
            if let result = viewModel.hookTestResult {
                ScrollView {
                    Text(result).font(.caption.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                    .frame(maxHeight: 120)
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 480)
        .fileImporter(isPresented: $selecting, allowedContentTypes: [.item]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                     includingResourceValuesForKeys: nil, relativeTo: nil)
                let command = HookCommand(bookmark: bookmark, displayPath: url.path)
                if selectingBefore { store.configuration.before = command } else { store.configuration.after = command }
                error = nil
            } catch { self.error = error.localizedDescription }
        }
    }

    @ViewBuilder
    private func commandEditor(before: Bool) -> some View {
        let binding = Binding<HookCommand?>(
            get: { before ? store.configuration.before : store.configuration.after },
            set: { if before { store.configuration.before = $0 } else { store.configuration.after = $0 } })
        Section(before ? "前置脚本" : "后置清理") {
            HStack {
                Text(binding.wrappedValue?.displayPath ?? String(localized: "未选择文件"))
                    .lineLimit(2).textSelection(.enabled)
                Spacer()
                Button("选择…") { selectingBefore = before; selecting = true }
                if binding.wrappedValue != nil { Button("清除") { binding.wrappedValue = nil } }
            }
            if binding.wrappedValue != nil {
                Toggle("使用 /bin/zsh -f 执行脚本", isOn: Binding(
                    get: { binding.wrappedValue?.shellScript ?? true },
                    set: { binding.wrappedValue?.shellScript = $0 }))
                TextField("参数（每行一个）", text: Binding(
                    get: { binding.wrappedValue?.arguments.joined(separator: "\n") ?? "" },
                    set: { binding.wrappedValue?.arguments = $0.isEmpty ? [] : $0.components(separatedBy: "\n") }),
                    axis: .vertical)
                    .lineLimit(2...5)
                Button("测试脚本（会实际执行）") {
                    guard let command = binding.wrappedValue else { return }
                    Task { await viewModel.testHook(command) }
                }
                .disabled(!viewModel.canStartTasks)
            }
        }
    }
}
