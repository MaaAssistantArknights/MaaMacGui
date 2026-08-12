//
//  CapsulePicker.swift
//  MAA
//
//  Created by hguandl on 2026/8/10.
//

import SwiftUI

struct CapsulePicker<Item: Identifiable, L1: View, L2: View>: View {
    @Binding private var selection: Item

    private let items: [Item]
    private let color: KeyPath<Item, Color>

    private let icon: (Item) -> L1
    private let text: (Item) -> L2

    private let action: (@MainActor () -> Void)?

    @Namespace private var namespace

    var body: some View {
        HStack {
            ForEach(items) { item in
                let selected = item.id == selection.id
                let color = item[keyPath: color]
                Button {
                    selection = item
                    action?()
                } label: {
                    let label = HStack(spacing: 4) {
                        icon(item)
                            .matchedGeometryEffect(id: color, in: namespace)
                        if selected {
                            text(item).fixedSize()
                        }
                    }
                    .font(.headline)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    if selected {
                        label.frame(maxWidth: .infinity)
                    } else {
                        label
                    }
                }
                .buttonStyle(ColoredCapsuleButtonStyle(color: color, selected: selected))
                .matchedGeometryEffect(id: item.id, in: namespace)
            }
        }
        .animation(.easeOut(duration: 0.2), value: selection.id)
    }
}

private struct ColoredCapsuleButtonStyle: ButtonStyle {
    let color: Color
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        let foregroundColor: Color
        let backgroundColor: Color

        if selected || configuration.isPressed {
            foregroundColor = .white
            backgroundColor = color
        } else {
            foregroundColor = .primary
            backgroundColor = Color(.secondarySystemFill)
        }

        return configuration.label
            .foregroundStyle(foregroundColor)
            .background(backgroundColor)
            .clipShape(.capsule)
    }
}

extension CapsulePicker {
    init<C: RandomAccessCollection>(
        _ data: C, selection: Binding<Item>, color: KeyPath<Item, Color>,
        @ViewBuilder icon: @escaping (Item) -> L1,
        @ViewBuilder text: @escaping (Item) -> L2,
        action: (@MainActor () -> Void)? = nil
    ) where C.Element == Item {
        self.items = Array(data)
        self._selection = selection
        self.color = color
        self.icon = icon
        self.text = text
        self.action = action
    }
}

#Preview {
    @Previewable @State var category = CopilotCategory.bundled
    List {
        EmptyView()
    }
    .safeAreaInset(edge: .top) {
        CapsulePicker(CopilotCategory.allCases, selection: $category, color: \.color) {
            Image(systemName: $0.systemImage)
        } text: {
            Text($0.title)
        }
        .padding()
    }
    .frame(maxWidth: 300)
}
