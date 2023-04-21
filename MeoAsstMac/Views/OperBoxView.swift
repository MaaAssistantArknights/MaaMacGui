//
//  OperBoxView.swift
//  MAA
//
//  Created by hguandl on 22/4/2023.
//

import SwiftUI

struct OperBoxView: View {
    @EnvironmentObject private var viewModel: MAAViewModel

    var body: some View {
        List {
            Section {
                ForEach(unownedOpers, id: \.id) { oper in
                    Text(oper.name)
                }
            } header: {
                Text("未拥有干员：\(unownedOpers.count)")
            }

            Section {
                ForEach(ownedOpers, id: \.id) { oper in
                    Text(oper.name)
                }
            } header: {
                Text("已拥有干员：\(ownedOpers.count)")
            }
        }
        .padding()
        .animation(.default, value: viewModel.operBox?.operbox)
    }

    var ownedOpers: [MAAOperBox.Oper] {
        viewModel.operBox?.operbox.filter(\.own) ?? []
    }

    var unownedOpers: [MAAOperBox.Oper] {
        viewModel.operBox?.operbox
            .filter { !$0.own }
            .filter { !excludedOperNames.contains($0.name) }
            ?? []
    }

    private let excludedOperNames = [
        "预备干员-近战",
        "预备干员-术师",
        "预备干员-后勤",
        "预备干员-狙击",
        "预备干员-重装",
        "郁金香",
        "Stormeye",
        "Touch",
        "Pith",
        "Sharp",
        "阿米娅-WARRIOR",
    ]
}

struct OperBoxView_Previews: PreviewProvider {
    static var previews: some View {
        OperBoxView()
    }
}
