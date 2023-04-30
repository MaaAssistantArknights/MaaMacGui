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
                    Text(prompt)
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

    private let prompt = "  在罗德岛竟然有这么多志同道合的志士。是的，诗歌！战争！自由！能在历史的洪流中汇集众人的力量，为这片大地的改变而奋斗。真是令人振奋！这些悲壮又非凡的故事，是应当被传颂下去的。"

    private let tips = [
        "保佑胜利的英雄，我将领受你们的祝福。",
        "伟大的战士们啊，我会在你们身边，与你们一同奋勇搏杀。",
        "再转身回头的时候，我们将带着胜利归来。",
        "不需畏惧，我们会战胜那些鲁莽的家伙！",
        "欢呼吧！",
        "来吧——",
        "现在可没有后悔的余地了。",
        "无需退路。",
        "英雄们啊，为这最强大的信念，请站在我们这边。",
        "颤抖吧，在真正的勇敢面前。",
        "哭嚎吧，为你们不堪一击的信念。",
        "你将在此跪拜。",
        "是吗，我们做到了吗......我现在，正体会至高的荣誉和幸福。",
        "转身吧，勇士们。我们已经获得了完美的胜利，现在是该回去享受庆祝的盛典了。",
        "听啊，悲鸣停止了。这是幸福的和平到来前的宁静。",
        "纵使人类的战争没尽头......在这一刻，我们守护住了自己生的尊严。离开吧。但要昂首挺胸。",
        "这对角可能会不小心撞倒些家具，我会尽量小心。",
    ]
}

struct GachaView_Previews: PreviewProvider {
    static var previews: some View {
        GachaView()
    }
}
