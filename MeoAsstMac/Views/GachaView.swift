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
    @State private var showNotice = true

    var body: some View {
        if showNotice {
            Text("请注意，这是真的抽卡！不是模拟！！！")
                .font(.title)
                .bold()

            Button("我已知晓，继续") {
                showNotice = false
            }
        } else {
            gachaContent
        }
    }

    @ViewBuilder private var gachaContent: some View {
        VStack {
            Group {
                if showTips {
                    Text(tips.randomElement()!)
                } else {
                    Text("GachaInitTip")
                }
            }
            .font(.headline)
            .padding()

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

    // MARK: - State Wrappers

    private var showTips: Bool {
        submitted || screenshot != nil
    }

    // MARK: - Constant Texts

    private let tips = [
        String(localized: "GachaTip1"),
        String(localized: "GachaTip2"),
        String(localized: "GachaTip3"),
        String(localized: "GachaTip4"),
        String(localized: "GachaTip5"),
        String(localized: "GachaTip6"),
        String(localized: "GachaTip7"),
        String(localized: "GachaTip8"),
        String(localized: "GachaTip9"),
        String(localized: "GachaTip10"),
        String(localized: "GachaTip11"),
        String(localized: "GachaTip12"),
        String(localized: "GachaTip13"),
        String(localized: "GachaTip14"),
        String(localized: "GachaTip15"),
        String(localized: "GachaTip16"),
        String(localized: "GachaTip17"),
    ]
}

struct GachaView_Previews: PreviewProvider {
    static var previews: some View {
        GachaView()
    }
}
