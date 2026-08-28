//
//  MallSettingsView.swift
//  MeoAsstMac
//
//  Created by hguandl on 9/10/2022.
//

import SwiftUI

struct MallSettingsView: View {
    @Environment(\.defaultMinListRowHeight) private var rowHeight

    @Binding var config: MallConfiguration

    var body: some View {
        VStack(spacing: 30) {
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                GridRow {
                    Toggle("访问好友基建", isOn: $config.visitFriends)
                }
                GridRow {
                    Toggle("信用购物", isOn: $config.shopping)
                    Toggle("信用溢出时无视黑名单", isOn: $config.force_shopping_if_credit_full)
                }
                GridRow {
                    Toggle("只购买折扣物品", isOn: $config.only_buy_discount)
                    Toggle("信用点不溢出后停止购买", isOn: $config.reserve_max_credit)
                }
                GridRow {
                    Toggle("借助战赚信用", isOn: $config.creditFight)
                    Picker("编队栏位", selection: $config.formationIndex) {
                        Text("当前").tag(0)
                        ForEach(1...4, id: \.self) { index in
                            Text("\(index)").tag(index)
                        }
                    }
                    .disabled(!config.creditFight)
                }
            }

            HStack(spacing: 20) {
                EditableTextList(title: "优先购买", texts: $config.buy_first)
                EditableTextList(title: "黑名单", texts: $config.blacklist)
            }
            .frame(minHeight: 6 * rowHeight, maxHeight: 12 * rowHeight)
        }
        .padding()
    }
}

struct MallSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        MallSettingsView(config: .constant(.init()))
    }
}

// MARK: - EditableTextList

private struct EditableTextList: View {
    let title: LocalizedStringKey
    @Binding var texts: [String]

    private struct TextEntry: Equatable, Identifiable {
        let id: Int
        var element: String
    }

    private var entries: Binding<[TextEntry]> {
        Binding {
            texts.enumerated().map { TextEntry(id: $0.offset, element: $0.element) }
        } set: { newValue in
            texts = newValue.map(\.element)
        }
    }

    @State private var selection: Int?
    @FocusState private var focusedField: Int?

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(entries) { entry in
                    HStack {
                        TextField("", text: entry.element)
                            .focused($focusedField, equals: entry.id)

                        Button {
                            selection = entry.id
                            focusedField = entry.id
                        } label: {
                            Image(systemName: "pencil")
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onMove(perform: moveEntry)
            } header: {
                Text(title)
            } footer: {
                editButtons()
            }
        }
        .animation(.default, value: texts)
    }

    @ViewBuilder private func editButtons() -> some View {
        HStack {
            Button {
                addEntry()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)

            Button {
                deleteEntry()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
    }

    private func moveEntry(source: IndexSet, destination: Int) {
        texts.move(fromOffsets: source, toOffset: destination)
    }

    private func addEntry() {
        texts.append("")
        selection = texts.count - 1
    }

    private func deleteEntry() {
        if let selection {
            texts.remove(at: selection)
        }
        selection = nil
    }
}
