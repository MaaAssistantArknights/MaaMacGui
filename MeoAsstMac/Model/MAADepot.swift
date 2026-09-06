//
//  MAADepot.swift
//  MAA
//
//  Created by hguandl on 19/4/2023.
//

import Foundation

struct MAADepot: Codable {
    let done: Bool
    var arkplanner: Arkplanner
    var lolicon: Lolicon
    private var cachedInventory: [String: Int]

    struct Arkplanner: Codable {
        var object: ArkplannerObject
        var data: String

        init(object: ArkplannerObject = .init(items: []), data: String = "") {
            self.object = object
            self.data = data
        }
    }

    struct ArkplannerObject: Codable {
        var items: [ArkplannerItem]
    }

    struct ArkplannerItem: Codable {
        let id: String
        var have: Int
        var name: String
    }

    struct Lolicon: Codable {
        var object: [String: Int]
        var data: String

        init(object: [String: Int] = [:], data: String = "") {
            self.object = object
            self.data = data
        }
    }

    private enum CodingKeys: String, CodingKey {
        case done
        case arkplanner
        case lolicon
        case data
        case cachedInventory
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        done = try container.decodeIfPresent(Bool.self, forKey: .done) ?? false
        arkplanner = try container.decodeIfPresent(Arkplanner.self, forKey: .arkplanner) ?? .init()
        lolicon = try container.decodeIfPresent(Lolicon.self, forKey: .lolicon) ?? .init()

        if let cached = try container.decodeIfPresent([String: Int].self, forKey: .cachedInventory) {
            cachedInventory = cached
        } else if let data = try? container.decode([String: Int].self, forKey: .data) {
            cachedInventory = data
        } else if let data = try? container.decode(String.self, forKey: .data),
            let raw = data.data(using: .utf8),
            let parsed = try? JSONDecoder().decode([String: Int].self, from: raw)
        {
            cachedInventory = parsed
        } else if !arkplanner.object.items.isEmpty {
            cachedInventory = Dictionary(uniqueKeysWithValues: arkplanner.object.items.map { ($0.id, $0.have) })
        } else {
            cachedInventory = lolicon.object
        }

        if arkplanner.object.items.isEmpty {
            arkplanner.object.items = cachedInventory.map {
                .init(id: $0.key, have: $0.value, name: $0.key)
            }
        }
        if lolicon.object.isEmpty {
            lolicon.object = cachedInventory
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(done, forKey: .done)
        try container.encode(arkplanner, forKey: .arkplanner)
        try container.encode(lolicon, forKey: .lolicon)
        try container.encode(cachedInventory, forKey: .cachedInventory)
    }

    func count(of itemID: String) -> Int? {
        cachedInventory[itemID]
    }

    func itemID(named name: String) -> String? {
        arkplanner.object.items.first { $0.name == name }?.id
    }

    mutating func addDrops(_ drops: [(id: String, name: String, quantity: Int)]) {
        for drop in drops where drop.quantity > 0 && Int(drop.id) != nil {
            let newCount = (cachedInventory[drop.id] ?? 0) + drop.quantity
            cachedInventory[drop.id] = newCount
            lolicon.object[drop.id] = newCount

            if let index = arkplanner.object.items.firstIndex(where: { $0.id == drop.id }) {
                arkplanner.object.items[index].have = newCount
            } else {
                arkplanner.object.items.append(.init(id: drop.id, have: newCount, name: drop.name))
            }
        }

        if let data = try? JSONEncoder().encode(lolicon.object) {
            lolicon.data = String(data: data, encoding: .utf8) ?? lolicon.data
        }
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
