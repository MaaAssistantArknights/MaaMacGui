//
//  Reclamation.swift
//  LegacyUserTasks
//
//  Created by hguandl on 19/4/2023.
//

import Foundation

@frozen public struct LegacyReclamationConfiguration: Codable {
    public let enable: Bool
    public let theme: LegacyReclamationTheme
    public let mode: Int
    public let tool_to_craft: String
    public let num_craft_batches: Int
    public let increment_mode: Int
}

@frozen public enum LegacyReclamationTheme: String, Codable {
    case fire = "Fire"
    case tales = "Tales"
}
