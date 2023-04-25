//
//  MAADepot.swift
//  MAA
//
//  Created by hguandl on 19/4/2023.
//

import Foundation

struct MAADepot: Codable {
    let done: Bool
    let arkplanner: Arkplanner
    let lolicon: Lolicon
    
    struct Arkplanner: Codable {
        let object: ArkplannerObject
        let data: String
    }
    
    struct ArkplannerObject: Codable {
        let items: [ArkplannerItem]
    }
    
    struct ArkplannerItem: Codable {
        let id: String
        let have: Int
        let name: String
    }
    
    struct Lolicon: Codable {
        let object: [String: Int]
        let data: String
    }
}

extension MAADepot: CustomStringConvertible {
    var contents: [String] {
        arkplanner.object.items
            .sorted { $0.id < $1.id }
            .map { "\($0.name): \($0.have)" }
    }
    
    var description: String {
        contents.joined(separator: "\n")
    }
}
