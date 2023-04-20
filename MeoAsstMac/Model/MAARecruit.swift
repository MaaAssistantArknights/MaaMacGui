//
//  MAARecruit.swift
//  MAA
//
//  Created by hguandl on 19/4/2023.
//

import Foundation

struct MAARecruit: Codable {
    let tags: [String]
    let level: Int
    let result: [MAARecruit.Result]

    struct Result: Codable {
        let tags: [String]
        let level: Int
        let opers: [MAARecruit.Operator]
    }

    struct Operator: Codable {
        let name: String
        let level: Int
    }
}
