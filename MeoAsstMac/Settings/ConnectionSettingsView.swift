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
            Picker("触控模式", selection: $viewModel.touchMode) {
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

            Toggle(isOn: allowGzip) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("允许使用 Gzip")
                    Text("使用 Gzip 压缩有可能会出现内存泄漏，非测试用途建议关闭。")
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
        .padding()
        .animation(.default, value: viewModel.touchMode)
    }

    private var allowGzip: Binding<Bool> {
        Binding {
            viewModel.connectionProfile == "Compatible"
        } set: { allow in
            if allow {
                viewModel.connectionProfile = "Compatible"
            } else {
                viewModel.connectionProfile = "CompatMac"
            }
        }
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
