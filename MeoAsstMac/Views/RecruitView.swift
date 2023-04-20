//
//  RecruitView.swift
//  MAA
//
//  Created by hguandl on 18/4/2023.
//

import SwiftUI

struct RecruitView: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    @State private var lv3ShortTime = false

    var body: some View {
        VStack {
            configView()

            Divider()

            Group {
                if let recruit = viewModel.recruit {
                    resultView(recruit: recruit)
                } else {
                    Text("RecruitmentRecognitionTip")
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .padding(.top)
        }
        .padding()
    }

    @ViewBuilder private func configView() -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading) {
                Toggle("自动设置时间", isOn: $viewModel.recruitConfig.set_time)
                Text("自动选择 Tags：")
            }

            VStack(alignment: .leading) {
                Toggle("3星设置7:40而非9:00", isOn: $lv3ShortTime)
                HStack {
                    Toggle("3星", isOn: autoSelect(level: 3))
                    Toggle("4星", isOn: autoSelect(level: 4))
                    Toggle("5星", isOn: autoSelect(level: 5))
                    Toggle("6星", isOn: autoSelect(level: 6))
                }
            }
        }
        .onChange(of: lv3ShortTime) { newValue in
            viewModel.recruitConfig.recruitment_time["3"] = newValue ? 460 : 540
        }
    }

    @ViewBuilder private func resultView(recruit: MAARecruit) -> some View {
        Text(recruit.tags.joined(separator: ", "))
        List(recruit.result, id: \.tags.hashValue) { result in
            Section {
                Text("\(result.opers.map(\.name).joined(separator: ", "))")
            } header: {
                Text("\(result.level)★ \(result.tags.joined(separator: " "))")
            }
        }
    }

    // MARK: - State Bingings

    private func autoSelect(level: Int) -> Binding<Bool> {
        Binding {
            viewModel.recruitConfig.select.contains(level)
        } set: { newValue in
            if newValue {
                var levels = Set(viewModel.recruitConfig.select)
                levels.insert(level)
                viewModel.recruitConfig.select = levels.sorted()
            } else {
                viewModel.recruitConfig.select.removeAll { $0 == level }
            }
        }
    }
}

struct RecruitView_Previews: PreviewProvider {
    static var previews: some View {
        RecruitView()
            .environmentObject(MAAViewModel())
            .frame(width: 360, height: 480)
    }
}
