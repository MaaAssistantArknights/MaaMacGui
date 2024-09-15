//
//  CheckForUpdatesView.swift
//  MAA
//
//  Created by hguandl on 11/3/2023.
//

import Sparkle
import SwiftUI

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button(NSLocalizedString("检查更新…", comment: ""), action: updater.checkForUpdates)
            .disabled(!viewModel.canCheckForUpdates)
    }
}

struct CheckForUpdatesView_Previews: PreviewProvider {
    private static let updateController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    static var previews: some View {
        CheckForUpdatesView(updater: updateController.updater)
    }
}
