//
//  LogView.swift
//  MAA
//
//  Created by hguandl on 16/4/2023.
//

import SwiftUI

struct LogView: View {
    @EnvironmentObject private var viewModel: MAAViewModel

    var body: some View {
        ScrollViewReader { proxy in
            Table(viewModel.logs) {
                TableColumn(NSLocalizedString("时间", comment: ""), value: \.date.maaFormat)
                    .width(min: 100, ideal: 125, max: 150)
                TableColumn(NSLocalizedString("信息", comment: "")) { log in
                    Text(log.content)
                        .textSelection(.enabled)
                        .foregroundColor(log.color.textColor)
                }
                .width(min: 100, ideal: 300)
            }
            .animation(.default, value: viewModel.logs)
            .toolbar {
                HStack {
                    Divider()

                    Toggle(isOn: $viewModel.trackTail) {
                        Label(NSLocalizedString("现在", comment: ""), systemImage: "arrow.down.to.line")
                            .foregroundColor(viewModel.trackTail ? Color.accentColor : nil)
                    }
                    .help(NSLocalizedString("自动滚动到底部", comment: ""))
                }
            }
            .onChange(of: viewModel.logs) { _ in
                if viewModel.trackTail {
                    withAnimation {
                        proxy.scrollTo(viewModel.logs.last?.id ?? UUID())
                    }
                }
            }
            .onChange(of: viewModel.trackTail) { newValue in
                if newValue {
                    withAnimation {
                        proxy.scrollTo(viewModel.logs.last?.id ?? UUID())
                    }
                }
            }
        }
    }
}

private extension Date? {
    var maaFormat: String {
        guard let self else { return "" }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM-dd HH:mm:ss"
        return dateFormatter.string(from: self)
    }
}

struct LogView_Previews: PreviewProvider {
    static var previews: some View {
        LogView().environmentObject(MAAViewModel())
    }
}
