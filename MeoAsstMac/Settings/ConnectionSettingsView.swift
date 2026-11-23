//
//  ConnectionSettingsView.swift
//  MeoAsstMac
//
//  Created by hguandl on 10/10/2022.
//

import ApplicationServices
import AppKit
import SwiftUI

struct ConnectionSettingsView: View {
    @EnvironmentObject private var viewModel: MAAViewModel

    var body: some View {
        VStack(alignment: .leading) {
            Picker("触控模式", selection: $viewModel.touchMode.animation()) {
                ForEach(MaaTouchMode.allCases, id: \.self) { mode in
                    Text(mode.displayName)
                }
            }

#if arch(arm64) && WITH_MAC_NATIVE
            if viewModel.touchMode == .MacNative {
                HStack {
                    Text("Bundle ID")
                    TextField("", text: $viewModel.macNativeBundleID)
                        .autocorrectionDisabled()
                }

                VStack(alignment: .leading, spacing: 8) {
                    if CGPreflightScreenCaptureAccess() {
                        Text(String(localized: "Screen Recording permission: Enabled"))
                    } else {
                        Text(String(localized: "Screen Recording permission: Required"))
                        Button(String(localized: "Open Screen Recording Settings")) {
                            if CGRequestScreenCaptureAccess() { return }
                            if let url = systemScreenCapturePreferenceURL {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }

                    if AXIsProcessTrusted() {
                        Text(String(localized: "Accessibility permission: Enabled"))
                    } else {
                        Text(String(localized: "Accessibility permission: Required"))
                        Button(String(localized: "Open Accessibility Settings")) {
                            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
                            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
                            if let url = accessibilityPreferenceURL {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(String(localized: "MacNative is experimental and supports screenshots, clicks, and straight swipes only."))
                    .font(.caption).foregroundStyle(.secondary)
                Text(String(localized: "Requires macOS 14 or later."))
                    .font(.caption).foregroundStyle(.secondary)
                Text(String(localized: "Text input, account switching, game launch, and deployment pauses are unsupported."))
                    .font(.caption).foregroundStyle(.secondary)
                Text(String(localized: "Start the game and keep its window open. Minimized or hidden windows are not supported."))
                    .font(.caption).foregroundStyle(.secondary)
            } else if viewModel.touchMode == .MacPlayTools {
                TextField("连接地址", text: $viewModel.connectionAddress)
            } else {
                HStack {
                    Text("连接地址")
                    TextField("", text: $viewModel.connectionAddress)
                }
            }
#else
            if viewModel.touchMode == .MacPlayTools {
                Text("PlayTools 的使用请参考[文档](https://maa.plus/docs/zh-cn/manual/device/macos.html)。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            TextField("连接地址", text: $viewModel.connectionAddress)
#endif

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
            } else if viewModel.touchMode.rawValue != "MacNative" {
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
#if arch(arm64) && WITH_MAC_NATIVE
    case MacNative
#endif

    var displayName: String {
        switch self {
#if arch(arm64) && WITH_MAC_NATIVE
        case .MacNative:
            String(localized: "Native macOS Control (Experimental)")
#endif
        default:
            rawValue
        }
    }
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

private let accessibilityPreferenceURL = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
