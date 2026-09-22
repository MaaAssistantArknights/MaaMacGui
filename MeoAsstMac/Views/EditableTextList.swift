//
//  EditableTextList.swift
//  MAA
//
//  Created by zhangweijian on 22/9/2026.
//

import SwiftUI

struct EditableTextList: View {
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
