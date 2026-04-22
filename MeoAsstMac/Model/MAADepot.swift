//
//  MAADepot.swift
//  MAA
//
//  Created by hguandl on 19/4/2023.
//

import Foundation

struct MAADepot: Codable {
    let done: Bool
    let data: String
}

extension MAADepot: CustomStringConvertible {
    var contents: [String] {
        do {
            let depot = try JSONDecoder().decode([String: Int].self, from: Data(data.utf8))
            return depot
                .sorted { $0.key < $1.key }
                .map { "\(MAADepot.arkItems[$0.key]?.name ?? $0.key): \($0.value)" }
        } catch {
            return []
        }
    }

    var description: String {
        contents.joined(separator: "\n")
    }

    private static let arkItems: [String: DropItem] = {
        guard let url = Bundle.main.resourceURL?
            .appendingPathComponent("resource")
            .appendingPathComponent("item_index.json"),
            let data = try? Data(contentsOf: url),
            let json = try? JSONDecoder().decode([String: DropItem].self, from: data)
        else {
            return [:]
        }
        return json
    }()

    var arkPlannerExportText: String {
        do {
            let depot = try JSONDecoder().decode([String: Int].self, from: Data(data.utf8))
            let items = depot
                .filter { $0.value > 0 }
                .compactMap { entry -> [String: Any]? in
                    guard let item = MAADepot.arkItems[entry.key] else { return nil }
                    return ["id": entry.key, "have": entry.value, "name": item.name]
                }
            let export: [String: Any] = [
                "@type": "@penguin-statistics/depot",
                "items": items
            ]
            return try String(data: JSONSerialization.data(withJSONObject: export), encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    var loliconExportText: String {
        do {
            let depot = try JSONDecoder().decode([String: Int].self, from: Data(data.utf8))
            var export: [String: Int] = [:]
            depot
                .filter { $0.value > 0 }
                .forEach { export[$0.key] = $0.value }
            return try String(data: JSONSerialization.data(withJSONObject: export), encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
