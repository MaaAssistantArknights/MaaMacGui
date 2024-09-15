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
                ForEach(ownedOpers, id: \.id) { oper in
                    oper.label
                }
            } header: {
                Text("已拥有干员：\(ownedOpers.count)")
            }

            Section {
                ForEach(unownedOpers, id: \.id) { oper in
                    Text(oper.name)
                }
            } header: {
                Text("未拥有干员：\(unownedOpers.count)")
            }
        }
        .padding()
        .animation(.default, value: viewModel.operBox)
    }

    var ownedOpers: [MAAOperBox.OwnedOper] {
        viewModel.operBox?.own_opers
            .sorted()
            ?? []
    }

    var unownedOpers: [MAAOperBox.Oper] {
        viewModel.operBox?.all_opers
            .filter { !$0.own }
            .filter { !excludedOperNames.contains($0.name) }
            ?? []
    }

    private let excludedOperNames = [
        NSLocalizedString("预备干员-近战", comment: ""),
        NSLocalizedString("预备干员-术师", comment: ""),
        NSLocalizedString("预备干员-后勤", comment: ""),
        NSLocalizedString("预备干员-狙击", comment: ""),
        NSLocalizedString("预备干员-重装", comment: ""),
        NSLocalizedString("郁金香", comment: ""),
        "Stormeye",
        "Touch",
        "Pith",
        "Sharp",
        NSLocalizedString("阿米娅-WARRIOR", comment: ""),
    ]
}

struct OperBoxView_Previews: PreviewProvider {
    static var previews: some View {
        OperBoxView()
    }
}
