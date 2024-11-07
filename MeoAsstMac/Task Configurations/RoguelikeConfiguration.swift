//
//  RoguelikeConfiguration.swift
//  MAA
//
//  Created by hguandl on 16/4/2023.
//

import Foundation

struct RoguelikeConfiguration: MAATaskConfiguration {
    var enable = false
    var theme = RoguelikeTheme.Phantom {
        didSet {
            if !theme.difficulties.contains(where: { $0.id == difficulty }) {
                difficulty = theme.difficulties.first!.id
            }
            if !theme.modes.contains(where: { $0.id == mode }) {
                mode = theme.modes.first!.id
            }
            if !theme.squads.contains(squad) {
                squad = theme.squads.first!
            }
        }
    }
    var difficulty = Int.max
    var mode = 0
    var starts_count = 9_999_999
    var investment_enabled = true
    var investments_count = 999
    var stop_when_investment_full = false
    var squad = "指挥分队"
    var roles = "取长补短"
    var core_char = ""
    var start_with_elite_two = false
    var only_start_with_elite_two = false
    var use_support = false
    var use_nonfriend_support = false
    var refresh_trader_with_dice = false

    var title: String {
        MAATask.TypeName.Roguelike.description
    }

    var subtitle: String {
        return theme.description
    }

    var summary: String {
        "\(RoguelikeDifficulty(id: difficulty).description) \(RoguelikeMode(id: mode).shortDescription)"
    }
}

extension RoguelikeConfiguration {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.enable = try container.decode(Bool.self, forKey: .enable)
        self.theme = try container.decode(RoguelikeTheme.self, forKey: .theme)
        self.mode = try container.decode(Int.self, forKey: .mode)
        self.starts_count = try container.decode(Int.self, forKey: .starts_count)
        self.investment_enabled = try container.decode(Bool.self, forKey: .investment_enabled)
        self.investments_count = try container.decode(Int.self, forKey: .investments_count)
        self.stop_when_investment_full = try container.decode(Bool.self, forKey: .stop_when_investment_full)
        self.squad = try container.decode(String.self, forKey: .squad)
        self.roles = try container.decode(String.self, forKey: .roles)
        self.core_char = try container.decode(String.self, forKey: .core_char)

        // Migration
        self.use_support = (try? container.decode(Bool.self, forKey: .use_support)) ?? false
        self.use_nonfriend_support = (try? container.decode(Bool.self, forKey: .use_nonfriend_support)) ?? false
        self.refresh_trader_with_dice = (try? container.decode(Bool.self, forKey: .refresh_trader_with_dice)) ?? false
        self.start_with_elite_two = (try? container.decode(Bool.self, forKey: .start_with_elite_two)) ?? false
        self.only_start_with_elite_two = (try? container.decode(Bool.self, forKey: .only_start_with_elite_two)) ?? false
        self.difficulty = (try? container.decode(Int.self, forKey: .difficulty)) ?? -1
    }
}
