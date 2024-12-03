//
//  Closedown.swift
//  LegacyUserTasks
//
//  Created by hguandl on 2024/7/22.
//

import Foundation

@frozen public struct LegacyClosedownConfiguration: Codable {
    public let enable: Bool
    public let client_type: LegacyMAAClientChannel
}

extension LegacyClosedownConfiguration {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.enable = try container.decode(Bool.self, forKey: .enable)
        self.client_type = (try? container.decode(LegacyMAAClientChannel.self, forKey: .client_type)) ?? .default
    }
}
