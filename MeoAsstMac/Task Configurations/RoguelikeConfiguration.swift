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
        case JieGarden
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

    var theme: Theme {
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
    var mode: Mode {
        didSet {
            use_foldartal = mode != .clpPds
            check_collapsal_paradigms = mode == .clpPds
        }
    }
    var squad: String
    var roles: String
    var core_char: String
    var use_support: Bool
    var use_nonfriend_support: Bool
    var starts_count: Int
    /// 指定难度等级，可选，默认值 `0`
    ///
    /// 仅适用于**除 `Phantom` 以外**的主题
    var difficulty: Difficulty
    /// 是否在第 5 层险路恶敌节点前停止任务，可选，默认值 `false`
    ///
    /// 仅适用于**除 `Phantom` 以外**的主题
    var stop_at_final_boss: Bool
    var stop_at_max_level: Bool
    var investment_enabled: Bool
    var investments_count: Int
    var stop_when_investment_full: Bool
    /// 是否在投资后尝试购物，可选，默认值 `false`
    ///
    /// 仅适用于模式 `investment`
    var investment_with_more_score: Bool
    /// 是否在凹开局的同时凹干员精二直升，可选，默认值 `false`
    ///
    /// 仅适用于模式 `collectible`
    var start_with_elite_two: Bool
    /// 是否只凹开局干员精二直升而忽视其他开局条件，可选，默认值 `false`
    ///
    /// 仅在模式为 `collectible` 且 `start_with_elite_two` 为 `true` 时有效
    var only_start_with_elite_two: Bool
    /// 是否用骰子刷新商店购买特殊商品，可选，默认值 `false`
    ///
    /// 仅适用于 `Mizuki` 主题，用于刷指路鳞
    var refresh_trader_with_dice: Bool
    /// 希望在第一层远见阶段得到的密文版，若成功凹到则停止任务，可选
    ///
    /// 仅适用于 `Sami` 主题
    var first_floor_foldartal: String
    /// 凹开局时希望在开局奖励阶段得到的密文板，可选，默认值 `[]`
    ///
    /// 仅在主题为 `Sami` 模式为 `collectible` 且使用 "生活至上分队" 时有效；
    var start_foldartal_list: [String]
    /// 是否凹 2 构想开局，可选，默认值 `false`
    ///
    /// 仅在主题为 `Sarkaz` 且模式为 `collectible` 时有效
    var start_with_two_ideas: Bool
    /// 是否使用密文板，模式 `clpPds` 下默认值 `false`，其他模式下默认值 `true`
    ///
    /// 仅适用于 `Sami` 主题
    var use_foldartal: Bool
    /// 是否检测获取的坍缩范式，模式 `clpPds` 下默认值 `true`，其他模式下默认值 `false`
    ///
    /// 仅适用于 `Sami` 主题
    var check_collapsal_paradigms: Bool
    /// 希望触发的坍缩范式，默认值为稀有坍缩
    ///
    /// 仅在主题为 `Sami` 且模式为 `clpPds` 时有效
    var expected_collapsal_paradigms: [String]
    /// 是否启动月度小队自动切换
    ///
    /// 仅在模式为 `squad` 时有效
    var monthly_squad_auto_iterate: Bool
    /// 是否将月度小队通信也作为切换依据
    ///
    /// 仅在模式为 `squad` 且 `monthlySquadAutoIterate` 为 `true` 时有效
    var monthly_squad_check_comms: Bool
    /// 是否启动深入调查自动切换
    ///
    /// 仅在模式为 `exploration` 时有效
    var deep_exploration_auto_iterate: Bool
    /// 烧水是否启用购物, 默认值 `false`
    ///
    /// 仅在模式为 `collectible` 时有效
    var collectible_mode_shopping: Bool
    /// 烧水时使用的分队, 默认与 `squad` 同步
    ///
    /// 仅在模式为 `collectible` 时有效
    var collectible_mode_squad: String
    /// 烧水期望奖励, 默认全 `false`
    ///
    /// 仅在模式为 `collectible` 时有效
    var collectible_mode_start_list: StartCollectibles

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

    struct Params: Encodable {
        let theme: String?
        let mode: Int?
        let squad: String?
        let roles: String?
        let core_char: String?
        let use_support: Bool?
        let use_nonfriend_support: Bool?
        let starts_count: Int?
        let difficulty: Int?
        let stop_at_final_boss: Bool?
        let stop_at_max_level: Bool?
        let investment_enabled: Bool?
        let investments_count: Int?
        let stop_when_investment_full: Bool?
        let investment_with_more_score: Bool?
        let start_with_elite_two: Bool?
        let only_start_with_elite_two: Bool?
        let refresh_trader_with_dice: Bool?
        let first_floor_foldartal: String?
        let start_foldartal_list: [String]?
        let start_with_two_ideas: Bool?
        let use_foldartal: Bool?
        let check_collapsal_paradigms: Bool?
        let expected_collapsal_paradigms: [String]?
        let monthly_squad_auto_iterate: Bool?
        let monthly_squad_check_comms: Bool?
        let deep_exploration_auto_iterate: Bool?
        let collectible_mode_shopping: Bool?
        let collectible_mode_squad: String?
        let collectible_mode_start_list: StartCollectibles?
    }

    var params: Params {
        Params(config: self)
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
        case .JieGarden:
            return NSLocalizedString("界园", comment: "")
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

    static let max = Self(id: Int(Int32.max))
    static let current = Self(id: -1)

    static func upto(maximum: Int) -> [Self] {
        [.current, .max] + (0...maximum).reversed().map { Self(id: $0) }
    }
}

extension RoguelikeConfiguration.Params {
    init(config: RoguelikeConfiguration) {
        self.theme = config.theme.rawValue
        self.mode = config.mode.rawValue
        self.squad = config.squad
        self.roles = config.roles
        self.core_char = config.core_char
        self.use_support = config.use_support
        self.use_nonfriend_support = config.use_support ? config.use_nonfriend_support : nil
        self.starts_count = config.starts_count
        self.difficulty = config.theme != .Phantom ? config.difficulty.id : nil
        self.stop_at_final_boss = config.theme != .Phantom ? config.stop_at_final_boss : nil
        self.stop_at_max_level = config.stop_at_max_level
        self.investment_enabled = config.investment_enabled
        self.investments_count = config.investments_count
        self.stop_when_investment_full = config.stop_when_investment_full
        self.investment_with_more_score = config.mode == .investment ? config.investment_with_more_score : nil
        self.start_with_elite_two = config.mode == .collectible ? config.start_with_elite_two : nil
        self.only_start_with_elite_two =
            config.mode == .collectible && config.start_with_elite_two ? config.only_start_with_elite_two : nil
        self.refresh_trader_with_dice = config.theme == .Mizuki ? config.refresh_trader_with_dice : nil
        self.first_floor_foldartal = config.theme == .Sami ? config.first_floor_foldartal : nil
        self.start_foldartal_list =
            config.theme == .Sami && config.mode == .collectible && config.squad == "生活至上分队"
            ? config.start_foldartal_list : nil
        self.start_with_two_ideas =
            config.theme == .Sarkaz && config.mode == .collectible ? config.start_with_two_ideas : nil
        self.use_foldartal = config.theme == .Sami ? config.use_foldartal : nil
        self.check_collapsal_paradigms = config.theme == .Sami ? config.check_collapsal_paradigms : nil
        self.expected_collapsal_paradigms =
            config.theme == .Sami && config.mode == .clpPds ? config.expected_collapsal_paradigms : nil
        self.monthly_squad_auto_iterate = config.mode == .squad ? config.monthly_squad_auto_iterate : nil
        self.monthly_squad_check_comms =
            config.mode == .squad && config.monthly_squad_auto_iterate ? config.monthly_squad_check_comms : nil
        self.deep_exploration_auto_iterate = config.mode == .exploration ? config.deep_exploration_auto_iterate : nil
        self.collectible_mode_shopping = config.mode == .collectible ? config.collectible_mode_shopping : nil
        self.collectible_mode_squad = config.mode == .collectible ? config.collectible_mode_squad : nil
        self.collectible_mode_start_list = config.mode == .collectible ? config.collectible_mode_start_list : nil
    }
}

extension RoguelikeConfiguration {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.theme = try container.decodeIfPresent(Theme.self, forKey: .theme) ?? .Phantom
        self.mode = try container.decodeIfPresent(Mode.self, forKey: .mode) ?? .exp
        self.squad = try container.decodeIfPresent(String.self, forKey: .squad) ?? "指挥分队"
        self.roles = try container.decodeIfPresent(String.self, forKey: .roles) ?? "取长补短"
        self.core_char = try container.decodeIfPresent(String.self, forKey: .core_char) ?? ""
        self.use_support = try container.decodeIfPresent(Bool.self, forKey: .use_support) ?? false
        self.use_nonfriend_support = try container.decodeIfPresent(Bool.self, forKey: .use_nonfriend_support) ?? false
        self.starts_count = try container.decodeIfPresent(Int.self, forKey: .starts_count) ?? 9_999_999
        self.difficulty = try container.decodeIfPresent(Difficulty.self, forKey: .difficulty) ?? .max
        self.stop_at_final_boss = try container.decodeIfPresent(Bool.self, forKey: .stop_at_final_boss) ?? false
        self.stop_at_max_level = try container.decodeIfPresent(Bool.self, forKey: .stop_at_max_level) ?? false
        self.investment_enabled = try container.decodeIfPresent(Bool.self, forKey: .investment_enabled) ?? true
        self.investments_count = try container.decodeIfPresent(Int.self, forKey: .investments_count) ?? 999
        self.stop_when_investment_full =
            try container.decodeIfPresent(Bool.self, forKey: .stop_when_investment_full) ?? false
        self.investment_with_more_score =
            try container.decodeIfPresent(Bool.self, forKey: .investment_with_more_score) ?? false
        self.start_with_elite_two = try container.decodeIfPresent(Bool.self, forKey: .start_with_elite_two) ?? false
        self.only_start_with_elite_two =
            try container.decodeIfPresent(Bool.self, forKey: .only_start_with_elite_two) ?? false
        self.refresh_trader_with_dice =
            try container.decodeIfPresent(Bool.self, forKey: .refresh_trader_with_dice) ?? false
        self.first_floor_foldartal = try container.decodeIfPresent(String.self, forKey: .first_floor_foldartal) ?? ""
        self.start_foldartal_list = try container.decodeIfPresent([String].self, forKey: .start_foldartal_list) ?? []
        self.start_with_two_ideas = try container.decodeIfPresent(Bool.self, forKey: .start_with_two_ideas) ?? false
        self.use_foldartal = try container.decodeIfPresent(Bool.self, forKey: .use_foldartal) ?? true
        self.check_collapsal_paradigms =
            try container.decodeIfPresent(Bool.self, forKey: .check_collapsal_paradigms) ?? false
        self.expected_collapsal_paradigms =
            try container.decodeIfPresent([String].self, forKey: .expected_collapsal_paradigms) ?? [
                "目空一些", "睁眼瞎", "图像损坏", "一抹黑",
            ]
        self.monthly_squad_auto_iterate =
            try container.decodeIfPresent(Bool.self, forKey: .monthly_squad_auto_iterate) ?? false
        self.monthly_squad_check_comms =
            try container.decodeIfPresent(Bool.self, forKey: .monthly_squad_check_comms) ?? false
        self.deep_exploration_auto_iterate =
            try container.decodeIfPresent(Bool.self, forKey: .deep_exploration_auto_iterate) ?? false
        self.collectible_mode_shopping =
            try container.decodeIfPresent(Bool.self, forKey: .collectible_mode_shopping) ?? false
        self.collectible_mode_squad =
            try container.decodeIfPresent(String.self, forKey: .collectible_mode_squad) ?? "指挥分队"
        self.collectible_mode_start_list =
            try container.decodeIfPresent(StartCollectibles.self, forKey: .collectible_mode_start_list)
            ?? StartCollectibles()
    }
}
