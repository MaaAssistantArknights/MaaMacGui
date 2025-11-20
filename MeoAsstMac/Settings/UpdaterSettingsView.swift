//
//  UpdaterSettingsView.swift
//  MeoAsstMac
//
//  Created by hguandl on 13/3/2023.
//

import Sparkle
import SwiftUI

struct UpdaterSettingsView: View {
    private let updater: SPUUpdater

    @State private var automaticallyChecksForUpdates: Bool
    @State private var automaticallyDownloadsUpdates: Bool

    @AppStorage("MaaUseBetaChannel") private var useBetaChannel = false
    @AppStorage("AutoResourceUpdate") var autoResourceUpdate = false
    @AppStorage("ResourceUpdateChannel") var resourceChannel = MAAResourceChannel.github

    init(updater: SPUUpdater) {
        self.updater = updater
        self.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        self.automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
    }

    var body: some View {
        Form {
            Toggle("接收开发版更新", isOn: $useBetaChannel)

            Toggle("自动检查更新", isOn: $automaticallyChecksForUpdates)
                .onChange(of: automaticallyChecksForUpdates) { newValue in
                    updater.automaticallyChecksForUpdates = newValue
                }

            Toggle("自动下载更新", isOn: $automaticallyDownloadsUpdates)
                .disabled(!automaticallyChecksForUpdates)
                .onChange(of: automaticallyDownloadsUpdates) { newValue in
                    updater.automaticallyDownloadsUpdates = newValue
                }

            Divider()

            Picker("资源更新来源", selection: $resourceChannel) {
                ForEach(MAAResourceChannel.allCases, id: \.hashValue) { channel in
                    Text(channel.description).tag(channel)
                }
            }

            if resourceChannel == .mirrorChyan {
                SecureField("CDK", text: mirrorChyanCDK)
            } else if resourceChannel == .github {
                Text("可能需要设置系统代理。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Toggle("自动资源更新", isOn: $autoResourceUpdate)

            Text("重新打开应用后生效。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .animation(.default, value: resourceChannel)
        .padding()
    }
}

private let mirrorChyanCDK = Binding {
    MirrorChyan.getCDK() ?? ""
} set: {
    _ = MirrorChyan.setCDK($0)
}

struct UpdaterSettingsView_Previews: PreviewProvider {
    private static let updateController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    static var previews: some View {
        UpdaterSettingsView(updater: updateController.updater)
    }
}
