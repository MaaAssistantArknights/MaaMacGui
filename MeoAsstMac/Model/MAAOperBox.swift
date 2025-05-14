//
//  MAAOperBox.swift
//  MAA
//
//  Created by hguandl on 22/4/2023.
//

import SwiftUI

struct MAAOperBox: Codable, Hashable {
    let done: Bool
    let all_opers: [Oper]
    let own_opers: [OwnedOper]

    struct Oper: Codable, Hashable {
        let id: String
        let own: Bool
        let name: String
        let rarity: Int
    }

    struct OwnedOper: Codable, Hashable {
        let id: String
        let own: Bool
        let name: String
        let rarity: Int

        let elite: Int
        let level: Int
        let potential: Int
    }
}

extension MAAOperBox.OwnedOper: Comparable {
    static func < (lhs: MAAOperBox.OwnedOper, rhs: MAAOperBox.OwnedOper) -> Bool {
        for predicate in sortPredicates {
            switch (predicate(lhs, rhs), predicate(rhs, lhs)) {
            case (true, _):
                return true
            case (_, true):
                return false
            case (false, false):
                break
            }
        }
        return false
    }

    private static let sortPredicates: [(Self, Self) -> Bool] = [
        { $0.elite > $1.elite },
        { $0.level > $1.level },
        { $0.rarity > $1.rarity },
        { $0.id < $1.id },
    ]
}

extension MAAOperBox.OwnedOper {
    @ViewBuilder var label: some View {
        HStack(spacing: 20) {
            Text(name)
            Text("精英\(elite) Lv\(level) 潜能\(potential)")
                .foregroundColor(.secondary)
        }
    }
}
