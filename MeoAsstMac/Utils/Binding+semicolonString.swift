//
//  Binding+semicolonString.swift
//  MAA
//
//  Created by hguandl on 2025/2/11.
//

import SwiftUI

extension Binding {
    func semicolonString(for keyPath: WritableKeyPath<Value, [String]>) -> Binding<String> {
        Binding<String> {
            wrappedValue[keyPath: keyPath].joined(separator: "; ")
        } set: { newValue in
            wrappedValue[keyPath: keyPath] = newValue.split(separator: ";").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
        }
    }
}
