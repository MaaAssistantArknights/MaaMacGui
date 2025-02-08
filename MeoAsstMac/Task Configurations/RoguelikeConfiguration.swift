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

    struct StartCollectibles: Codable, Hashable {
        var hot_water = false
        var shield = false
        var ingot = false
        var hope = false
        var random = false
        var key = false
        var dice = false
        var ideas = false
    }

    var theme = Theme.Phantom {
        didSet {
            if !theme.difficulties.contains(difficulty) {
                difficulty = theme.difficulties.first ?? .init(id: 0)
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
    /// 指定难度等级，可选，默认值 `0`
    ///
    /// 仅适用于**除 `Phantom` 以外**的主题
    var difficulty = Difficulty(id: 0)
    /// 是否在第 5 层险路恶敌节点前停止任务，可选，默认值 `false`
    ///
    /// 仅适用于**除 `Phantom` 以外**的主题
    var stop_at_final_boss = false
    var stop_at_max_level = false
    var investment_enabled = true
    var investments_count = 999
    var stop_when_investment_full = false
    /// 是否在投资后尝试购物，可选，默认值 `false`
    ///
    /// 仅适用于模式 `investment`
    var investment_with_more_score = false
    /// 是否在凹开局的同时凹干员精二直升，可选，默认值 `false`
    ///
    /// 仅适用于模式 `collectible`
    var start_with_elite_two = false
    /// 是否只凹开局干员精二直升而忽视其他开局条件，可选，默认值 `false`
    ///
    /// 仅在模式为 `collectible` 且 `start_with_elite_two` 为 `true` 时有效
    var only_start_with_elite_two = false
    /// 是否用骰子刷新商店购买特殊商品，可选，默认值 `false`
    ///
    /// 仅适用于 `Mizuki` 主题，用于刷指路鳞
    var refresh_trader_with_dice = false
    /// 希望在第一层远见阶段得到的密文版，若成功凹到则停止任务，可选
    ///
    /// 仅适用于 `Sami` 主题
    var first_floor_foldartal = ""
    /// 凹开局时希望在开局奖励阶段得到的密文板，可选，默认值 `[]`
    ///
    /// 仅在主题为 `Sami` 模式为 `collectible` 且使用 "生活至上分队" 时有效；
    var start_foldartal_list = [String]()
    /// 是否凹 2 构想开局，可选，默认值 `false`
    ///
    /// 仅在主题为 `Sarkaz` 且模式为 `collectible` 时有效
    var start_with_two_ideas = false
    /// 是否使用密文板，模式 `clpPds` 下默认值 `false`，其他模式下默认值 `true`
    ///
    /// 仅适用于 `Sami` 主题
    var use_foldartal = true
    /// 是否检测获取的坍缩范式，模式 `clpPds` 下默认值 `true`，其他模式下默认值 `false`
    ///
    /// 仅适用于 `Sami` 主题
    var check_collapsal_paradigms = false
    /// 是否执行坍缩范式检测防漏措施，模式 `clpPds` 下默认值 true，其他模式下默认值 `false`
    ///
    /// 仅在主题为 `Sami` 且 `check_collapsal_paradigms` 为 `true` 时有效
    var double_check_collapsal_paradigms = false
    /// 希望触发的坍缩范式，默认值为稀有坍缩
    ///
    /// 仅在主题为 `Sami` 且模式为 `clpPds` 时有效
    var expected_collapsal_paradigms = ["目空一些", "睁眼瞎", "图像损坏", "一抹黑"]
    /// 是否启动月度小队自动切换
    ///
    /// 仅在模式为 `squad` 时有效
    var monthlySquadAutoIterate = false
    /// 是否将月度小队通信也作为切换依据
    ///
    /// 仅在模式为 `squad` 且 `monthlySquadAutoIterate` 为 `true` 时有效
    var monthlySquadCheckComms = false
    /// 是否启动深入调查自动切换
    ///
    /// 仅在模式为 `exploration` 时有效
    var deepExplorationAutoIterate = false
    /// 烧水是否启用购物, 默认值 `false`
    ///
    /// 仅在模式为 `collectible` 时有效
    var collectible_mode_shopping = false
    /// 烧水时使用的分队, 默认与 `squad` 同步
    ///
    /// 仅在模式为 `collectible` 时有效
    var collectible_mode_squad = "指挥分队"
    /// 烧水期望奖励, 默认全 `false`
    ///
    /// 仅在模式为 `collectible` 时有效
    var collectible_mode_start_list = StartCollectibles()

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
        self.squad = try container.decode(String.self, forKey: .squad)
        self.roles = try container.decode(String.self, forKey: .roles)
        self.core_char = try container.decode(String.self, forKey: .core_char)
        self.starts_count = try container.decode(Int.self, forKey: .starts_count)
        self.investment_enabled = try container.decode(Bool.self, forKey: .investment_enabled)
        self.investments_count = try container.decode(Int.self, forKey: .investments_count)
        self.stop_when_investment_full = try container.decode(Bool.self, forKey: .stop_when_investment_full)

        // Migration
        self.use_support = (try? container.decode(Bool.self, forKey: .use_support)) ?? false
        self.use_nonfriend_support = (try? container.decode(Bool.self, forKey: .use_nonfriend_support)) ?? false
        self.difficulty = (try? container.decode(Difficulty.self, forKey: .difficulty)) ?? .max
        self.stop_at_final_boss = try container.decodeIfPresent(Bool.self, forKey: .stop_at_final_boss) ?? false
        self.stop_at_max_level = try container.decodeIfPresent(Bool.self, forKey: .stop_at_max_level) ?? false
        self.investment_with_more_score =
            try container.decodeIfPresent(Bool.self, forKey: .investment_with_more_score) ?? false
        self.start_with_elite_two = (try? container.decode(Bool.self, forKey: .start_with_elite_two)) ?? false
        self.only_start_with_elite_two = (try? container.decode(Bool.self, forKey: .only_start_with_elite_two)) ?? false
        self.refresh_trader_with_dice = (try? container.decode(Bool.self, forKey: .refresh_trader_with_dice)) ?? false
        self.first_floor_foldartal = try container.decodeIfPresent(String.self, forKey: .first_floor_foldartal) ?? ""
        self.start_foldartal_list = try container.decodeIfPresent([String].self, forKey: .start_foldartal_list) ?? []
        self.start_with_two_ideas = try container.decodeIfPresent(Bool.self, forKey: .start_with_two_ideas) ?? false
        self.use_foldartal = try container.decodeIfPresent(Bool.self, forKey: .use_foldartal) ?? true
        self.check_collapsal_paradigms =
            try container.decodeIfPresent(Bool.self, forKey: .check_collapsal_paradigms) ?? false
        self.double_check_collapsal_paradigms =
            try container.decodeIfPresent(Bool.self, forKey: .double_check_collapsal_paradigms) ?? false
        self.expected_collapsal_paradigms =
            try container.decodeIfPresent([String].self, forKey: .expected_collapsal_paradigms) ?? [
                "目空一些", "睁眼瞎", "图像损坏", "一抹黑",
            ]
        self.monthlySquadCheckComms = try container.decodeIfPresent(Bool.self, forKey: .monthlySquadCheckComms) ?? false
        self.deepExplorationAutoIterate =
            try container.decodeIfPresent(Bool.self, forKey: .deepExplorationAutoIterate) ?? false
        self.collectible_mode_shopping =
            try container.decodeIfPresent(Bool.self, forKey: .collectible_mode_shopping) ?? false
        self.collectible_mode_squad =
            try container.decodeIfPresent(String.self, forKey: .collectible_mode_squad) ?? "指挥分队"
        self.collectible_mode_start_list =
            try container.decodeIfPresent(StartCollectibles.self, forKey: .collectible_mode_start_list)
            ?? StartCollectibles()
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
            return "难度\(id)"
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
        case stop_at_final_boss
        case stop_at_max_level
        case stop_when_investment_full
        case investment_with_more_score
        case start_with_elite_two
        case only_start_with_elite_two
        case refresh_trader_with_dice
        case first_floor_foldartal
        case start_foldartal_list
        case start_with_two_ideas
        case use_foldartal
        case check_collapsal_paradigms
        case double_check_collapsal_paradigms
        case expected_collapsal_paradigms
        case monthlySquadAutoIterate
        case monthlySquadCheckComms
        case deepExplorationAutoIterate
        case collectible_mode_shopping
        case collectible_mode_squad
        case collectible_mode_start_list
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
            try container.encode(stop_at_final_boss, forKey: .stop_at_final_boss)
        }
        try container.encode(stop_at_max_level, forKey: .stop_at_max_level)
        try container.encode(investment_enabled, forKey: .investment_enabled)
        try container.encode(investments_count, forKey: .investments_count)
        try container.encode(stop_when_investment_full, forKey: .stop_when_investment_full)
        if mode == .investment {
            try container.encode(investment_with_more_score, forKey: .investment_with_more_score)
        }
        if mode == .collectible {
            try container.encode(start_with_elite_two, forKey: .start_with_elite_two)
            if start_with_elite_two {
                try container.encode(only_start_with_elite_two, forKey: .only_start_with_elite_two)
            }
        }
        if theme == .Mizuki {
            try container.encode(refresh_trader_with_dice, forKey: .refresh_trader_with_dice)
        }
        if theme == .Sami {
            try container.encode(first_floor_foldartal, forKey: .first_floor_foldartal)
            if mode == .collectible, squad == "生活至上分队" {
                try container.encode(start_foldartal_list, forKey: .start_foldartal_list)
            }
        }
        if theme == .Sarkaz, mode == .collectible {
            try container.encode(start_with_two_ideas, forKey: .start_with_two_ideas)
        }
        if theme == .Sami {
            try container.encode(check_collapsal_paradigms, forKey: .check_collapsal_paradigms)
            if check_collapsal_paradigms {
                try container.encode(double_check_collapsal_paradigms, forKey: .double_check_collapsal_paradigms)
            }
            if mode == .clpPds {
                try container.encode(expected_collapsal_paradigms, forKey: .expected_collapsal_paradigms)
            }
        }
        if mode == .squad {
            try container.encode(monthlySquadAutoIterate, forKey: .monthlySquadAutoIterate)
            if monthlySquadAutoIterate {
                try container.encode(monthlySquadCheckComms, forKey: .monthlySquadCheckComms)
            }
        }
        if mode == .exploration {
            try container.encode(deepExplorationAutoIterate, forKey: .deepExplorationAutoIterate)
        }
        if mode == .collectible {
            try container.encode(collectible_mode_shopping, forKey: .collectible_mode_shopping)
            try container.encode(collectible_mode_squad, forKey: .collectible_mode_squad)
            try container.encode(collectible_mode_start_list, forKey: .collectible_mode_start_list)
        }
    }
}
