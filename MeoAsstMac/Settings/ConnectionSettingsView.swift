//
//  ConnectionSettingsView.swift
//  MeoAsstMac
//
//  Created by hguandl on 10/10/2022.
//

import SwiftUI

struct ConnectionSettingsView: View {
    @EnvironmentObject private var viewModel: MAAViewModel

    var body: some View {
        VStack(alignment: .leading) {
            Picker("连接配置", selection: $viewModel.connectionMode) {
                Text("通用 / PlayCover").tag(MaaConnectionMode.automatic)
                Text("腾讯应用宝 Mac").tag(MaaConnectionMode.androwsMac)
            }

            Picker("触控模式", selection: $viewModel.touchMode.animation()) {
                ForEach(MaaTouchMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue)
                }
            }
            .disabled(viewModel.connectionMode == .androwsMac)

            if viewModel.effectiveTouchMode == .MacPlayTools {
                Text("PlayTools 的使用请参考[文档](https://maa.plus/docs/zh-cn/manual/device/macos.html)。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Text("连接地址")
                TextField("", text: $viewModel.connectionAddress)
            }

            Divider()

            if viewModel.effectiveTouchMode == .MacPlayTools {
                Picker("截图模式", selection: $viewModel.toolsMode.animation()) {
                    ForEach(MaaToolsMode.allCases, id: \.self) { mode in
                        Text(mode.description)
                    }
                }

                if viewModel.toolsMode == .MacSCK {
                    if CGPreflightScreenCaptureAccess() {
                        Text("✅ 屏幕录制权限已开启")
                    } else {
                        Text("⚠️ 屏幕录制权限未开启")
                        Button("打开录屏权限设置") {
                            if CGRequestScreenCaptureAccess() {
                                return
                            }
                            if let url = systemScreenCapturePreferenceURL {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            } else if viewModel.connectionMode == .androwsMac {
                Text("请先启动游戏，并在游戏设置中选择客户端。游戏重启后请重新连接。此模式使用 ADB 触控，关闭 adb-lite，允许 Gzip 截图。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Toggle(isOn: $viewModel.useGzip) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("允许使用 Gzip")
                        Text("如果出现内存泄漏请尝试关闭此功能。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $viewModel.useAdbLite) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("使用 adb-lite 连接")
                        Text("实验性功能，理论性能更好。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
    }
}

struct ConnectionSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        ConnectionSettingsView()
            .environmentObject(MAAViewModel())
    }
}

enum MaaTouchMode: String, CaseIterable {
    case adb
    case minitouch
    case maatouch
    case MacPlayTools
}

enum MaaToolsMode: String, CaseIterable {
    case RGBA
    case BGR
    case MacSCK
}

extension MaaToolsMode: CustomStringConvertible {
    var description: String {
        switch self {
        case .RGBA:
            String(localized: "默认兼容模式")
        case .BGR:
            String(localized: "优化加速模式")
        case .MacSCK:
            String(localized: "系统屏幕捕捉")
        }
    }
}

private let systemScreenCapturePreferenceURL = URL(
    string: "x-apple.systempreferences:com.apple.PreferencePanes.Security?Privacy_ScreenCapture")

/// Keep existing connection selection as the default for saved installations.
enum MaaConnectionMode: String, CaseIterable {
    case automatic
    case androwsMac

    func profile(touchMode: MaaTouchMode, toolsMode: MaaToolsMode, useGzip: Bool) -> String {
        if self == .androwsMac {
            return "AndrowsMac"
        }
        switch (touchMode, toolsMode, useGzip) {
        case (.MacPlayTools, .MacSCK, _):
            return "MacSCK"
        case (.MacPlayTools, .BGR, _):
            return "MacBGR"
        case (_, _, true):
            return "Compatible"
        default:
            return "CompatMac"
        }
    }
}
