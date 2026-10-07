import AppKit
import MaaCore
import SwiftUI

struct PlayCoverDiagnosticsView: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    @StateObject private var access = PlayCoverAccess()
    @StateObject private var model = PlayCoverDiagnosticModel()
    @State private var copied = false

    private var snapshot: PlayCoverDiagnosticSnapshot {
        .init(
            address: viewModel.connectionAddress, touchMode: viewModel.touchMode.rawValue,
            screenshotMode: viewModel.toolsMode.rawValue, clientName: viewModel.clientChannel.description,
            bundleID: viewModel.clientChannel.appBundleID,
            guiVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知",
            coreVersion: AsstGetVersion().map { String(cString: $0) } ?? "未知")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("检查 PlayCover、游戏与 MAA 的设置，并验证连接和截图。")
                .foregroundStyle(.secondary)
            HStack {
                Button(model.report == nil ? String(localized: "开始检测") : String(localized: "重新检测")) {
                    copied = false
                    model.start(snapshot: snapshot, access: access, runtimeAllowed: viewModel.status == .idle)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isDetecting)
                if model.isDetecting {
                    ProgressView().controlSize(.small)
                    Text(model.phase).font(.callout).foregroundStyle(.secondary)
                    Button("取消") { model.cancel() }
                }
                Spacer()
                Button(copied ? String(localized: "已复制") : String(localized: "复制报告")) {
                    guard let report = model.report else { return }
                    var text = report.text(homePath: PlayCoverAccess.userHome.path)
                    if model.needsRefresh { text += "\n配置或授权已变化，请重新检测。" }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                }
                .disabled(model.report == nil || model.isDetecting)
            }
            HStack {
                Button("启动游戏并继续检测") {
                    copied = false
                    model.start(
                        snapshot: snapshot, access: access, runtimeAllowed: viewModel.status == .idle, launch: true)
                }
                .disabled(model.isDetecting || viewModel.status != .idle)
                Text("已运行时仅继续检测。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("检测路径") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button("自定义 PlayCover 应用") { choose(.application) }
                        Text(
                            access.applicationURL.path.replacingOccurrences(
                                of: PlayCoverAccess.userHome.path, with: "~")
                        )
                        .foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("自定义数据目录") { choose(.data) }
                        Text(
                            access.dataURL.path.replacingOccurrences(of: PlayCoverAccess.userHome.path, with: "~")
                        )
                        .foregroundStyle(.secondary)
                    }
                    Button("恢复默认路径") {
                        access.useDefaultLocations()
                        model.needsRefresh = model.report != nil
                    }
                    Text("默认路径直接读取；若系统询问是否允许访问其他 App 数据，请选择允许。自定义路径仅保存只读授权。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .disabled(model.isDetecting)
            }
            if let message = access.message {
                Label(message, systemImage: "folder.badge.questionmark").foregroundStyle(.secondary)
            }
            if model.needsRefresh {
                Label("配置或授权已变化，请重新检测。", systemImage: "arrow.clockwise")
                    .foregroundStyle(.orange)
            }
            if viewModel.status != .idle {
                Label("MAA 正在执行任务，仅进行静态检查。", systemImage: "pause.circle")
                    .foregroundStyle(.secondary)
            }
            Divider()
            if let report = model.report {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(PlayCoverDiagnosticGroup.allCases) { group in
                            let items = report.items.filter { $0.group == group }
                            if !items.isEmpty {
                                GroupBox {
                                    VStack(alignment: .leading, spacing: 12) {
                                        ForEach(items) { item in DiagnosticItemView(item: item) }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(4)
                                } label: {
                                    Text(group.title).font(.headline)
                                }
                            }
                        }
                    }
                    .textSelection(.enabled)
                }
            } else {
                ContentUnavailableView(
                    "等待检测", systemImage: "stethoscope",
                    description: Text("点击开始检测；若系统询问是否允许访问其他 App 数据，请选择允许。游戏未启动时也可检查配置。"))
            }
        }
        .padding(8)
        .frame(minWidth: 450)
        .onChange(of: snapshot) { _, _ in model.needsRefresh = model.report != nil }
        .onChange(of: viewModel.status) { _, status in
            if status != .idle { model.cancel(reason: "MAA 开始执行任务，运行检测已中断。") }
        }
        .onDisappear { model.cancel() }
    }

    private func choose(_ location: PlayCoverAccess.Location) {
        Task {
            await access.choose(location)
            model.needsRefresh = model.report != nil
        }
    }
}

private struct DiagnosticItemView: View {
    let item: PlayCoverDiagnosticItem
    private var color: Color {
        switch item.status {
        case .passed: .green
        case .error: .red
        case .warning: .orange
        case .unavailable: .secondary
        }
    }
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.status.symbol).foregroundStyle(color).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.title).fontWeight(.medium)
                    Spacer()
                    Text(item.status.title).font(.caption).foregroundStyle(color)
                }
                Text(item.value).font(.system(.callout, design: .monospaced))
                Text(item.reason).font(.callout).foregroundStyle(.secondary)
                if !item.remedy.isEmpty {
                    Text(item.remedy).font(.callout)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
