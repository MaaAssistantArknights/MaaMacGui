//
//  MAADepot.swift
//  MAA
//
//  Created by hguandl on 19/4/2023.
//

import Foundation
import JBirdCore

struct MAADepot {
    let done: Bool
    let items: [String: Int]
}

extension MAADepot: JSONInitializable {
    init(json: JSON) throws {
        done = try json["done"]
        do {
            items = try json["data"]
        } catch {
            let string: String = try json["data"]
            let data = try JSON(jsonString: string)
            items = try .init(json: data)
        }
    }
}
