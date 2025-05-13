//
//  MAACopilot.swift
//  MAA
//
//  Created by hguandl on 17/4/2023.
//

import Foundation

enum DifficultyFlags: Int, Codable {
    case none = 0
    case normal = 1
    case raid = 2
    case normal_raid = 3
}

struct MAACopilot: Codable, Equatable {
    let stage_name: String
    let opers: [Operator]
    let groups: [Group]?
    let minimum_required: String
    let doc: Documentation?
    var difficulty: DifficultyFlags? = nil

    // MARK: SSS

    let type: String?
    let equipment: [String]?
    let strategy: String?
    let tool_men: [String: Int]?

    struct Operator: Codable, Equatable {
        let name: String
        let skill: Int?
    }

    struct Group: Codable, Equatable {
        let name: String
        let opers: [Operator]
    }

    struct Documentation: Codable, Equatable {
        let title: String?
        let title_color: String?
        let details: String?
        let details_color: String?
    }
}

extension MAACopilot.Operator: CustomStringConvertible {
    var description: String {
        if let skill {
            return "\(name) \(skill)"
        } else {
            return name
        }
    }
}

extension MAACopilot {
    init?(url: URL) {
        do {
            let data = try Data(contentsOf: url)
            self = try JSONDecoder().decode(MAACopilot.self, from: data)
        } catch {
            return nil
        }
    }
}
