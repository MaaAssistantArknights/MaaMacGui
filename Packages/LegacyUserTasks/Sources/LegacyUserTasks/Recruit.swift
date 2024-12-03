//
//  Recruit.swift
//  LegacyUserTasks
//
//  Created by hguandl on 16/4/2023.
//

import Foundation

@frozen public struct LegacyRecruitConfiguration: Codable {
    public let enable: Bool
    public let refresh: Bool
    public let select: [Int]
    public let confirm: [Int]
    public let times: Int
    public let set_time: Bool
    public let expedite: Bool
    public let skip_robot: Bool
    public let recruitment_time: [String: Int]
}
