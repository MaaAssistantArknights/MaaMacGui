//
//  OperBoxView.swift
//  MAA
//
//  Created by hguandl on 22/4/2023.
//

import JBird
import SwiftUI

struct OperBoxView: View {
    @Environment(NewViewModel.self) private var viewModel

    @State private var copyState: Bool?

    var body: some View {
        VStack(spacing: 20) {
            Text("特别关注会影响干员识别准确率，如有特别关注干员识别错误请自行判断。").font(.headline)
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
            Button {
                guard let opers = viewModel.operBox?.own_opers else { return }
                do {
                    let string = try JSON(opers).stringify()
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    copyState = pasteboard.setString(string, forType: .string)
                } catch {
                    copyState = false
                }
            } label: {
                Label {
                    Text("拷贝干员列表JSON")
                } icon: {
                    switch copyState {
                    case nil:
                        Image(systemName: "doc.on.doc")
                    case true:
                        Image(systemName: "checkmark.circle").foregroundStyle(.green)
                    case false:
                        Image(systemName: "xmark.circle").foregroundStyle(.red)
                    }
                }
            }
            .animation(.default, value: copyState)
            .disabled(viewModel.operBox?.done != true)
            .onChange(of: viewModel.operBox?.done) {
                if $1 == false {
                    copyState = nil
                }
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
            .filter { !Self.excludedOperIDs.contains($0.id) }
            ?? []
    }

    private static let excludedOperIDs: Set<String> = [
        "char_504_rguard", "char_505_rcast", "char_506_rmedic", "char_507_rsnipe",
        "char_508_aguard", "char_509_acast", "char_510_amedic", "char_511_asnipe",
        "char_512_aprot", "char_513_apionr", "char_514_rdfend",
        "char_600_cpione", "char_601_cguard", "char_602_cdfend", "char_603_csnipe",
        "char_604_ccast", "char_605_cmedic", "char_606_csuppo", "char_607_cspec",
        "char_608_acpion", "char_609_acguad", "char_610_acfend", "char_611_acnipe",
        "char_612_accast", "char_613_acmedc", "char_614_acsupo", "char_615_acspec",
        "char_616_pithst", "char_617_sharp2",
        "char_1001_amiya2", "char_1037_amiya3",
    ]
}

struct OperBoxView_Previews: PreviewProvider {
    static var previews: some View {
        OperBoxView()
    }
}
