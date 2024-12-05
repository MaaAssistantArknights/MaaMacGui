//
//  Roguelike.swift
//  LegacyUserTasks
//
//  Created by hguandl on 16/4/2023.
//

import Foundation

@frozen public struct LegacyRoguelikeConfiguration: Codable {
    public let enable: Bool
    public let theme: LegacyRoguelikeTheme
    public let difficulty: Int
    public let mode: Int
    public let starts_count: Int
    public let investment_enabled: Bool
    public let investments_count: Int
    public let stop_when_investment_full: Bool
    public let squad: String
    public let roles: String
    public let core_char: String
    public let start_with_elite_two: Bool
    public let only_start_with_elite_two: Bool
    public let use_support: Bool
    public let use_nonfriend_support: Bool
    public let refresh_trader_with_dice: Bool
}

extension LegacyRoguelikeConfiguration {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.enable = try container.decode(Bool.self, forKey: .enable)
        self.theme = try container.decode(LegacyRoguelikeTheme.self, forKey: .theme)
        self.mode = try container.decode(Int.self, forKey: .mode)
        self.starts_count = try container.decode(Int.self, forKey: .starts_count)
        self.investment_enabled = try container.decode(Bool.self, forKey: .investment_enabled)
        self.investments_count = try container.decode(Int.self, forKey: .investments_count)
        self.stop_when_investment_full = try container.decode(Bool.self, forKey: .stop_when_investment_full)
        self.squad = try container.decode(String.self, forKey: .squad)
        self.roles = try container.decode(String.self, forKey: .roles)
        self.core_char = try container.decode(String.self, forKey: .core_char)
        self.use_support = (try? container.decode(Bool.self, forKey: .use_support)) ?? false
        self.use_nonfriend_support = (try? container.decode(Bool.self, forKey: .use_nonfriend_support)) ?? false
        self.refresh_trader_with_dice = (try? container.decode(Bool.self, forKey: .refresh_trader_with_dice)) ?? false
        self.start_with_elite_two = (try? container.decode(Bool.self, forKey: .start_with_elite_two)) ?? false
        self.only_start_with_elite_two = (try? container.decode(Bool.self, forKey: .only_start_with_elite_two)) ?? false
        self.difficulty = (try? container.decode(Int.self, forKey: .difficulty)) ?? -1
    }
}

@frozen public enum LegacyRoguelikeTheme: String, CaseIterable, Codable {
    case Phantom
    case Mizuki
    case Sami
    case Sarkaz
}
