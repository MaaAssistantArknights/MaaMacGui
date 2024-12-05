//
//  Mall.swift
//  LegacyUserTasks
//
//  Created by hguandl on 16/4/2023.
//

import Foundation

@frozen public struct LegacyMallConfiguration: Codable {
    public let enable: Bool
    public let shopping: Bool
    public let buy_first: [String]
    public let blacklist: [String]
    public let force_shopping_if_credit_full: Bool
}
