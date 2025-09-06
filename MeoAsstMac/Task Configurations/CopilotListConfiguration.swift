//
//  CopilotListConfiguration.swift
//  MAA
//
//  Created by ninekirin on 2025/5/6.
//

import Foundation

struct CopilotListConfiguration: Codable {
    var items: [CopilotItemConfiguration] = []
    var formation: Bool = true
    var add_trust: Bool = false
    var use_sanity_potion: Bool = false
    
    enum CodingKeys: String, CodingKey {
        case items
        case formation
        case add_trust 
        case use_sanity_potion
    }
}

extension CopilotListConfiguration {
    func jsonString() throws -> String {
        let encoder = JSONEncoder()
        let data = try encoder.encode(self)
        return String(data: data, encoding: .utf8) ?? ""
    }
}
