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

    init(updater: SPUUpdater) {
        self.updater = updater
        self.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        self.automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
    }

    var body: some View {
        Form {
            Toggle(NSLocalizedString("接收开发版更新", comment: ""), isOn: $useBetaChannel)

            Toggle(NSLocalizedString("自动检查更新", comment: ""), isOn: $automaticallyChecksForUpdates)
                .onChange(of: automaticallyChecksForUpdates) { newValue in
                    updater.automaticallyChecksForUpdates = newValue
                }

            Toggle(NSLocalizedString("自动下载更新", comment: ""), isOn: $automaticallyDownloadsUpdates)
                .disabled(!automaticallyChecksForUpdates)
                .onChange(of: automaticallyDownloadsUpdates) { newValue in
                    updater.automaticallyDownloadsUpdates = newValue
                }
        }
        .padding()
    }
}

struct UpdaterSettingsView_Previews: PreviewProvider {
    private static let updateController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    static var previews: some View {
        UpdaterSettingsView(updater: updateController.updater)
    }
}
