//
//  LogView.swift
//  MAA
//
//  Created by hguandl on 16/4/2023.
//

import SwiftUI

struct LogView: View {
    @Environment(NewViewModel.self) private var newModel

    var body: some View {
        ScrollViewReader { proxy in
            Table(newModel.logs) {
                TableColumn("时间", value: \.date.maaGuiLogFormat)
                    .width(min: 100, ideal: 125, max: 150)
                TableColumn("信息") { log in
                    Text(log.content)
                        .textSelection(.enabled)
                        .foregroundStyle(log.color.textColor)
                        .lineLimit(nil)
                }
                .width(min: 100, ideal: 300)
            }
            .animation(.default, value: newModel.logs)
            .toolbar {
                @Bindable var newModel = newModel
                Toggle(isOn: $newModel.trackTail) {
                    Label("现在", systemImage: "arrow.down.to.line")
                }
                .help("自动滚动到底部")
            }
            .onChange(of: newModel.logs) { _, newValue in
                if newModel.trackTail {
                    withAnimation {
                        proxy.scrollTo(newValue.last?.id ?? UUID())
                    }
                }
            }
            .onChange(of: newModel.trackTail) {
                if $1 {
                    withAnimation {
                        proxy.scrollTo(newModel.logs.last?.id ?? UUID())
                    }
                }
            }
        }
    }
}

struct LogView_Previews: PreviewProvider {
    static var previews: some View {
        LogView().environment(NewViewModel(parent: MAAViewModel()))
    }
}
