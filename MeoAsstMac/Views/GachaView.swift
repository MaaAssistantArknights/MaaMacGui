//
//  GachaView.swift
//  MAA
//
//  Created by hguandl on 30/4/2023.
//

import SwiftUI

struct GachaView: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    @State private var screenshot: NSImage?
    @State private var submitted = false

    var body: some View {
        VStack {
            if let screenshot {
                Image(nsImage: screenshot)
                    .resizable()
                    .scaledToFit()
            }

            if submitted {
                ProgressView().padding()
            }

            HStack {
                Button("寻访一次") {
                    gachaPoll(once: true)
                }

                Button("寻访十次") {
                    gachaPoll(once: false)
                }
            }
            .disabled(viewModel.status != .idle)
        }
        .padding()
        .animation(.default, value: submitted)
        .animation(.default, value: screenshot)
        .onReceive(viewModel.$status, perform: getScreenshot)
    }

    // MARK: - Actions

    private func gachaPoll(once: Bool) {
        Task {
            try await viewModel.gachaPoll(once: once)
            submitted = true
            screenshot = nil
        }
    }

    private func getScreenshot(_ status: MAAViewModel.Status) {
        guard submitted && status == .idle else {
            return
        }
        Task {
            submitted = false
            screenshot = try await viewModel.screenshot()
        }
    }
}

struct GachaView_Previews: PreviewProvider {
    static var previews: some View {
        GachaView()
    }
}
