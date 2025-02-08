//
//  RoguelikeConfiguration.swift
//  MAA
//
//  Created by hguandl on 16/4/2023.
//

import Foundation

struct RoguelikeConfiguration: MAATaskConfiguration {
    var type: MAATaskType { .Roguelike }

    enum Mode: Int, CaseIterable, Codable {
        /// 刷经验，尽可能稳定地打更多层数，不期而遇采用激进策略
        case exp = 0
        /// 刷源石锭，第一层投资完就退出，不期而遇采用保守策略
        case investment = 1
        /// 刷开局，以获得热水壶或者演讲稿开局或只凹直升，不期而遇采用保守策略
        case collectible = 4
        /// 刷隐藏坍缩范式，以增加坍缩值为最优先目标
        ///
        /// 萨米主题专用模式
        case clpPds = 5
        /// 月度小队，尽可能稳定抵达五层，不期而遇采用激进策略
        case squad = 6
        /// 深入调查，尽可能稳定地打更多层数，不期而遇采用激进策略
        case exploration = 7
    }

    enum Theme: String, CaseIterable, Codable {
        case Phantom
        case Mizuki
        case Sami
        case Sarkaz
    }

    struct Difficulty: Hashable, Identifiable {
        let id: Int
    }

    var theme = Theme.Phantom {
        didSet {
            if !theme.difficulties.contains(difficulty) {
                difficulty = theme.difficulties.first ?? .max
            }
            if !theme.modes.contains(mode) {
                mode = theme.modes.first ?? .exp
            }
            if !theme.squads.contains(squad) {
                squad = theme.squads.first ?? "指挥分队"
            }
        }
    }
    var mode = Mode.exp
    var squad = "指挥分队"
    var roles = "取长补短"
    var core_char = ""
    var use_support = false
    var use_nonfriend_support = false
    var starts_count = 9_999_999
    var difficulty = Difficulty.max
    var investment_enabled = true
    var investments_count = 999
    var stop_when_investment_full = false
    var start_with_elite_two = false
    var only_start_with_elite_two = false
    var refresh_trader_with_dice = false

    var title: String {
        type.description
    }

    var subtitle: String {
        return theme.shortDescription
    }

    var summary: String {
        "\(difficulty.description) \(mode.shortDescription) \(core_char)"
    }

    var projectedTask: MAATask {
        .roguelike(self)
    }

    typealias Params = Self

    var params: Self {
        self
    }
}

extension RoguelikeConfiguration.Theme {
    var shortDescription: String {
        switch self {
        case .Phantom:
            return NSLocalizedString("傀影", comment: "")
        case .Mizuki:
            return NSLocalizedString("水月", comment: "")
        case .Sami:
            return NSLocalizedString("萨米", comment: "")
        case .Sarkaz:
            return NSLocalizedString("萨卡兹", comment: "")
        }
    }

    var modes: [RoguelikeConfiguration.Mode] {
        let commonModes = [RoguelikeConfiguration.Mode.exp, .investment, .collectible, .squad, .exploration]
        if self == .Sami {
            return commonModes + [.clpPds]
        } else {
            return commonModes
        }
    }
}

extension RoguelikeConfiguration.Mode {
    var shortDescription: String {
        switch self {
        case .exp:
            NSLocalizedString("优先层数", comment: "")
        case .investment:
            NSLocalizedString("优先投资", comment: "")
        case .collectible:
            NSLocalizedString("凹开局", comment: "")
        case .clpPds:
            NSLocalizedString("刷坍缩", comment: "")
        case .squad:
            NSLocalizedString("月度小队", comment: "")
        case .exploration:
            NSLocalizedString("深入调查", comment: "")
        }
    }
}

extension RoguelikeConfiguration {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.theme = try container.decode(Theme.self, forKey: .theme)
        self.mode = try container.decode(Mode.self, forKey: .mode)
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
        self.difficulty = (try? container.decode(Difficulty.self, forKey: .difficulty)) ?? .max
    }
}

extension RoguelikeConfiguration.Difficulty: Codable, CustomStringConvertible {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.id = try container.decode(Int.self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(id)
    }

    var description: String {
        switch self {
        case .max:
            return NSLocalizedString("最高难度", comment: "")
        case .current:
            return NSLocalizedString("当前难度", comment: "")
        default:
            return "\(id)"
        }
    }

    static let max = Self(id: 999)
    static let current = Self(id: -1)

    static func upto(maximum: Int) -> [Self] {
        [.current, .max] + (0...maximum).reversed().map { Self(id: $0) }
    }
}

extension RoguelikeConfiguration {
    enum CodingKeys: String, CodingKey {
        case enable
        case theme
        case mode
        case squad
        case roles
        case core_char
        case use_support
        case use_nonfriend_support
        case starts_count
        case difficulty
        case investment_enabled
        case investments_count
        case stop_when_investment_full
        case start_with_elite_two
        case only_start_with_elite_two
        case refresh_trader_with_dice
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(theme, forKey: .theme)
        try container.encode(mode, forKey: .mode)
        try container.encode(squad, forKey: .squad)
        try container.encode(roles, forKey: .roles)
        try container.encode(core_char, forKey: .core_char)
        try container.encode(use_support, forKey: .use_support)
        if use_support {
            try container.encode(use_nonfriend_support, forKey: .use_nonfriend_support)
        }
        try container.encode(starts_count, forKey: .starts_count)

        if theme != .Phantom {
            try container.encode(difficulty, forKey: .difficulty)
        }
        try container.encode(investment_enabled, forKey: .investment_enabled)
        try container.encode(investments_count, forKey: .investments_count)
        try container.encode(stop_when_investment_full, forKey: .stop_when_investment_full)
        if mode == .collectible {
            try container.encode(start_with_elite_two, forKey: .start_with_elite_two)
            if start_with_elite_two {
                try container.encode(only_start_with_elite_two, forKey: .only_start_with_elite_two)
            }
        }
        if theme == .Mizuki {
            try container.encode(refresh_trader_with_dice, forKey: .refresh_trader_with_dice)
        }
    }
}
