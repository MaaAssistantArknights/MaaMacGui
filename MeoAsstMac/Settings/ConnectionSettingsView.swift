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
            Picker("触控模式", selection: $viewModel.touchMode.animation()) {
                ForEach(MaaTouchMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue)
                }
            }

            if viewModel.touchMode == .MacPlayTools {
                Text("PlayTools 的使用请参考[文档](https://maa.plus/docs/zh-cn/manual/device/macos.html)。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Text("连接地址")
                TextField("", text: $viewModel.connectionAddress)
            }

            Divider()

            if viewModel.touchMode == .MacPlayTools {
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
            NSLocalizedString("默认兼容模式", comment: "")
        case .BGR:
            NSLocalizedString("优化加速模式", comment: "")
        case .MacSCK:
            NSLocalizedString("系统屏幕捕捉", comment: "")
        }
    }
}

private let systemScreenCapturePreferenceURL = URL(
    string: "x-apple.systempreferences:com.apple.PreferencePanes.Security?Privacy_ScreenCapture")
