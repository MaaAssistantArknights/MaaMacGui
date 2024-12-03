//
//  Award.swift
//  LegacyUserTasks
//
//  Created by hguandl on 16/4/2023.
//

import Foundation

@frozen public struct LegacyAwardConfiguration: Codable {
    public let enable: Bool
    public let award: Bool
    public let mail: Bool
    public let recruit: Bool
    public let orundum: Bool
    public let mining: Bool
    public let specialaccess: Bool
}

extension LegacyAwardConfiguration {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.enable = try container.decode(Bool.self, forKey: .enable)
        self.award = try container.decodeIfPresent(Bool.self, forKey: .award) ?? false
        self.mail = try container.decodeIfPresent(Bool.self, forKey: .mail) ?? false
        self.recruit = try container.decodeIfPresent(Bool.self, forKey: .recruit) ?? false
        self.orundum = try container.decodeIfPresent(Bool.self, forKey: .orundum) ?? false
        self.mining = try container.decodeIfPresent(Bool.self, forKey: .mining) ?? false
        self.specialaccess = try container.decodeIfPresent(Bool.self, forKey: .specialaccess) ?? false
    }
}
