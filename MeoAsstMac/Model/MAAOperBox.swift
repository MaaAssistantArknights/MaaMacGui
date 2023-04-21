//
//  MAAOperBox.swift
//  MAA
//
//  Created by hguandl on 22/4/2023.
//

import Foundation

struct MAAOperBox: Codable {
    let done: Bool
    let operbox: [Oper]

    struct Oper: Codable, Hashable {
        let id: String
        let own: Bool
        let name: String
    }
}
