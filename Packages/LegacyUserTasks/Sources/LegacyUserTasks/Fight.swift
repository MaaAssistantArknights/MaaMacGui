//
//  Fight.swift
//  LegacyUserTasks
//
//  Created by hguandl on 16/4/2023.
//

import Foundation

@frozen public struct LegacyFightConfiguration: Codable {
    public let enable: Bool
    public let stage: String
    public let medicine: Int?
    public let expiring_medicine: Int?
    public let stone: Int?
    public let times: Int?
    public let series: Int?
    public let drops: [String: Int]?
    public let report_to_penguin: Bool
    public let penguin_id: String
    public let server: String
    public let client_type: String
    public let DrGrandet: Bool
}
