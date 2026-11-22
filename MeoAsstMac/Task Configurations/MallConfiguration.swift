//
//  MallConfiguration.swift
//  MAA
//
//  Created by hguandl on 16/4/2023.
//

import Foundation
import JBird

struct MallConfiguration: MAATaskConfiguration {
    var type: MAATaskType { .Mall }

    var shopping: Bool
    var buy_first: [String]
    var blacklist: [String]
    var force_shopping_if_credit_full: Bool
    var only_buy_discount: Bool
    var reserve_max_credit: Bool

    var visitFriends: Bool
    var creditFight: Bool
    var formationIndex: Int

    var creditFightDate: Date
    var friendVisitDate: Date

    var title: String {
        type.description
    }

    var subtitle: String {
        if shopping {
            return String(localized: "购物")
        } else {
            return String(localized: "不购物")
        }
    }

    var summary: String {
        buy_first.joined(separator: ";")
    }

    var projectedTask: MAATask {
        .mall(self)
    }

    // TODO: Run credit fight at most once per game day.
    // TODO: Skip friend visits after reaching the daily limit.
    @JSON.Builder var params: JSON {
        "visit_friends" => visitFriends
        "shopping" => shopping
        "buy_first" => buy_first
        "blacklist" => blacklist
        "force_shopping_if_credit_full" => force_shopping_if_credit_full
        "only_buy_discount" => only_buy_discount
        "reserve_max_credit" => reserve_max_credit
        "credit_fight" => creditFight
        if creditFight {
            "formation_index" => formationIndex
        }
    }
}

extension MallConfiguration {
    private static let itemIDsByName: [String: String] = {
        guard let url = Bundle.main.url(forResource: "item_index", withExtension: "json", subdirectory: "resource"),
            let data = try? Data(contentsOf: url),
            let items = try? JSONDecoder().decode([String: DropItem].self, from: data)
        else { return [:] }
        return Dictionary(grouping: items, by: { $0.value.name })
            .compactMapValues { $0.count == 1 ? $0.first?.key : nil }
    }()

    func localizedItems() async -> Self {
        func itemID(_ name: String) -> String { Self.itemIDsByName[name] ?? name }
        let names = await MAAProvider.shared.itemNames(for: Set((buy_first + blacklist).map(itemID)))
        func localized(_ name: String) -> String {
            guard let value = names[itemID(name)], !value.isEmpty else { return name }
            return value
        }
        var config = self
        config.buy_first = buy_first.map(localized)
        config.blacklist = blacklist.map(localized)
        return config
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.shopping = try container.decodeIfPresent(Bool.self, forKey: .shopping) ?? true
        self.buy_first = try container.decodeIfPresent([String].self, forKey: .buy_first) ?? ["招聘许可", "龙门币"]
        self.blacklist = try container.decodeIfPresent([String].self, forKey: .blacklist) ?? ["加急许可", "家具零件"]
        self.force_shopping_if_credit_full =
            try container.decodeIfPresent(Bool.self, forKey: .force_shopping_if_credit_full) ?? true
        self.only_buy_discount = try container.decodeIfPresent(Bool.self, forKey: .only_buy_discount) ?? false
        self.reserve_max_credit = try container.decodeIfPresent(Bool.self, forKey: .reserve_max_credit) ?? false

        self.visitFriends = container[.visitFriends, default: true]
        self.creditFight = container[.creditFight, default: false]
        self.formationIndex = container[.formationIndex, default: 0]

        self.creditFightDate = container[.creditFightDate, default: .distantPast]
        self.friendVisitDate = container[.friendVisitDate, default: .distantPast]
    }
}
