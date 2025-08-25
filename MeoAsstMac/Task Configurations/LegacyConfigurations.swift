//
//  LegacyConfigurations.swift
//  MAA
//
//  Created by hguandl on 2024/12/4.
//

import Foundation
import LegacyUserTasks

func migrateLegacyConfigurations() throws -> [DailyTask] {
    try legacyTasks().map { task in
        switch task {
        case .startup(let config):
            let task = MAATask.startup(.init(migrating: config))
            return .init(id: UUID(), task: task, enabled: config.enable)
        case .closedown(let config):
            let task = MAATask.closedown(.init(migrating: config))
            return .init(id: UUID(), task: task, enabled: config.enable)
        case .recruit(let config):
            let task = MAATask.recruit(.init(migrating: config))
            return .init(id: UUID(), task: task, enabled: config.enable)
        case .infrast(let config):
            let task = MAATask.infrast(.init(migrating: config))
            return .init(id: UUID(), task: task, enabled: config.enable)
        case .fight(let config):
            let task = MAATask.fight(.init(migrating: config))
            return .init(id: UUID(), task: task, enabled: config.enable)
        case .mall(let config):
            let task = MAATask.mall(.init(migrating: config))
            return .init(id: UUID(), task: task, enabled: config.enable)
        case .award(let config):
            let task = MAATask.award(.init(migrating: config))
            return .init(id: UUID(), task: task, enabled: config.enable)
        case .roguelike(let config):
            let task = MAATask.roguelike(.init(migrating: config))
            return .init(id: UUID(), task: task, enabled: config.enable)
        case .reclamation(let config):
            let task = MAATask.reclamation(.init(migrating: config))
            return .init(id: UUID(), task: task, enabled: config.enable)
        }
    }
}

extension StartupConfiguration {
    fileprivate init(migrating config: LegacyStartupConfiguration) {
        self.init()
        self.start_game_enabled = config.start_game_enabled
        self.client_type = .init(rawValue: config.client_type.rawValue) ?? .Official
    }
}

extension ClosedownConfiguration {
    fileprivate init(migrating config: LegacyClosedownConfiguration) {
        self.client_type = .init(rawValue: config.client_type.rawValue) ?? .Official
    }
}

extension RecruitConfiguration {
    fileprivate init(migrating config: LegacyRecruitConfiguration) {
        self.init()
        self.refresh = config.refresh
        self.select = config.select
        self.confirm = config.confirm
        self.times = config.times
        self.set_time = config.set_time
        self.expedite = config.expedite
        self.skip_robot = config.skip_robot
        self.recruitment_time = config.recruitment_time
    }
}

extension InfrastConfiguration {
    fileprivate init(migrating config: LegacyInfrastConfiguration) {
        self.mode = .init(rawValue: config.mode) ?? .default
        self.facility = config.facility.compactMap { .init(rawValue: $0.rawValue) }
        self.drones = .init(rawValue: config.drones.rawValue) ?? .NotUse
        self.threshold = config.threshold
        self.replenish = config.replenish
        self.dorm_notstationed_enabled = config.dorm_notstationed_enabled
        self.dorm_trust_enabled = config.dorm_trust_enabled
        self.filename = config.filename
        self.plan_index = config.plan_index
        self.continue_training = true
        self.reception_message_board = true
    }
}

extension FightConfiguration {
    fileprivate init(migrating config: LegacyFightConfiguration) {
        self.stage = config.stage
        self.medicine = config.medicine
        self.expiring_medicine = config.expiring_medicine
        self.stone = config.stone
        self.times = config.times
        self.series = config.series
        self.drops = config.drops
        self.report_to_penguin = config.report_to_penguin
        self.penguin_id = config.penguin_id
        self.server = config.server
        self.client_type = config.client_type
        self.DrGrandet = config.DrGrandet
    }
}

extension MallConfiguration {
    fileprivate init(migrating config: LegacyMallConfiguration) {
        self.init()
        self.shopping = config.shopping
        self.buy_first = config.buy_first
        self.blacklist = config.blacklist
        self.force_shopping_if_credit_full = config.force_shopping_if_credit_full
    }
}

extension AwardConfiguration {
    fileprivate init(migrating config: LegacyAwardConfiguration) {
        self.award = config.award
        self.mail = config.mail
        self.recruit = config.recruit
        self.orundum = config.orundum
        self.mining = config.mining
        self.specialaccess = config.specialaccess
    }
}

extension RoguelikeConfiguration {
    fileprivate init(migrating config: LegacyRoguelikeConfiguration) {
        self.init()
        self.theme = .init(rawValue: config.theme.rawValue) ?? .Phantom
        self.difficulty = .init(id: config.difficulty)
        self.mode = .init(rawValue: config.mode) ?? .exp
        self.starts_count = config.starts_count
        self.investment_enabled = config.investment_enabled
        self.investments_count = config.investments_count
        self.stop_when_investment_full = config.stop_when_investment_full
        self.squad = config.squad
        self.roles = config.roles
        self.core_char = config.core_char
        self.start_with_elite_two = config.start_with_elite_two
        self.use_support = config.use_support
        self.use_nonfriend_support = config.use_nonfriend_support
        self.refresh_trader_with_dice = config.refresh_trader_with_dice
    }
}

extension ReclamationConfiguration {
    fileprivate init(migrating config: LegacyReclamationConfiguration) {
        self.theme = .init(rawValue: config.theme.rawValue) ?? .tales
        self.mode = config.mode
        self.tools_to_craft = [config.tool_to_craft]
        self.num_craft_batches = config.num_craft_batches
        self.increment_mode = config.increment_mode
    }
}
