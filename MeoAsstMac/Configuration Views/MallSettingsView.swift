//
//  MallSettingsView.swift
//  MeoAsstMac
//
//  Created by hguandl on 9/10/2022.
//

import SwiftUI

struct MallSettingsView: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    @Environment(\.defaultMinListRowHeight) private var rowHeight
    let id: UUID

    private var config: Binding<MallConfiguration> {
        viewModel.taskConfig(id: id)
    }

    var body: some View {
        VStack(spacing: 30) {
            HStack(spacing: 10) {
                Spacer()
                Toggle(NSLocalizedString("信用购物", comment: ""), isOn: config.shopping)
                Toggle(NSLocalizedString("信用溢出时无视黑名单", comment: ""), isOn: config.force_shopping_if_credit_full)
                Toggle(NSLocalizedString("借助战赚信用", comment: ""), isOn: .constant(false))
                Spacer()
            }

            HStack(spacing: 20) {
                EditableTextList(title: NSLocalizedString("优先购买", comment: ""), texts: config.buy_first)
                EditableTextList(title: NSLocalizedString("黑名单", comment: ""), texts: config.blacklist)
            }
            .frame(height: 12 * rowHeight)
        }
        .padding()
    }
}

struct MallSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        MallSettingsView(id: UUID())
            .environmentObject(MAAViewModel())
    }
}

// MARK: - EditableTextList

private struct EditableTextList: View {
    let title: String
    @Binding var texts: [String]

    private struct TextEntry: Equatable, Identifiable {
        var id: Int
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

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(entries) { entry in
                    TextField("", text: entry.element)
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
