//
//  DepotView.swift
//  MAA
//
//  Created by hguandl on 18/4/2023.
//

import JBird
import SwiftUI

struct DepotView: View {
    @Environment(NewViewModel.self) private var viewModel

    @JSONRepresentable fileprivate struct Item: Identifiable {
        let id: String
        let have: Int
        let name: String
    }

    @State private var nameTaskToken: UUID?
    @State private var items = [Item]()

    var body: some View {
        VStack(spacing: 20) {
            List(items) { item in
                Text("\(item.name)：\(item.have)")
            }
            .task(id: viewModel.depot?.items) {
                guard let items = viewModel.depot?.items else { return }
                let token = UUID()
                nameTaskToken = token
                let names = await MAAProvider.shared.itemNames(for: items.keys)
                guard !Task.isCancelled else {
                    if nameTaskToken == token {
                        nameTaskToken = nil
                    }
                    return
                }
                self.items = items.sorted {
                    $0.key < $1.key
                }.map { (key, value) in
                    Item(key: key, value: value, name: names[key])
                }
                nameTaskToken = nil
            }

            HStack(spacing: 20) {
                Text("复制结果JSON至剪贴板：")

                Button("企鹅物流") {
                    copyToPasteboard(text: arkplannerPayload)
                    NSWorkspace.shared.open(URL(string: "https://penguin-stats.cn/planner")!)
                }
                .disabled(nameTaskToken != nil)
                Button("明日方舟工具箱") {
                    copyToPasteboard(text: arkntoolsPayload)
                    NSWorkspace.shared.open(URL(string: "https://arkntools.app/#/material")!)
                }
            }
            .disabled(viewModel.depot?.done != true)
        }
        .padding()
    }

    private func copyToPasteboard(text: String?) {
        guard let text else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private var arkntoolsPayload: String? {
        guard let items = viewModel.depot?.items else { return nil }
        return try? JSON(items).stringify()
    }

    private var arkplannerPayload: String? {
        let json = JSON {
            "@type" => "@penguin-statistics/depot"
            "items" => {
                for item in items {
                    item
                }
            }
        }
        return try? json.stringify()
    }
}

extension DepotView.Item: Hashable {
    init(key: String, value: Int, name: String?) {
        id = key
        have = value
        if let name, !name.isEmpty {
            self.name = name
        } else {
            self.name = key
        }
    }
}

struct DepotView_Previews: PreviewProvider {
    static var previews: some View {
        DepotView()
            .environment(NewViewModel(parent: MAAViewModel()))
    }
}
