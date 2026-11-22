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
    func localizedItems(for client: MAAClientChannel) -> Self {
        guard shopping, !buy_first.isEmpty || !blacklist.isEmpty else { return self }
        var config = self
        func names(for channel: MAAClientChannel, updated: URL?) throws -> [String: String] {
            struct Item: Decodable { let name: String }
            let path =
                channel.isGlobal
                ? "resource/global/\(channel.rawValue)/resource/item_index.json" : "resource/item_index.json"
            let url = updated?.appending(path: path)
            let source =
                url.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
                ?? Bundle.main.resourceURL!.appending(path: path)
            let data = try Data(contentsOf: source)
            let items = try JSONDecoder().decode([String: Item].self, from: data)
            guard !items.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            return items.mapValues(\.name)
        }
        let base: [String: String]
        let local: [String: String]
        let updated: URL?
        do {
            updated = try MAAResourceChannel.localVersion().preferUser ? URL.documentsDirectory : nil
            base = try names(for: .Official, updated: updated)
            local = client.isGlobal ? try names(for: client, updated: updated) : base
        } catch {
            config.buy_first = []
            config.shopping = blacklist.isEmpty
            return config
        }
        var itemsByName = Dictionary(grouping: base, by: \.value)
        let unknown = Set(buy_first + blacklist).filter {
            itemsByName[$0] == nil && base[$0] == nil && local[$0] == nil && !local.values.contains($0)
        }
        var checkedAllNames = true
        if !unknown.isEmpty {
            for channel in MAAClientChannel.allCases where channel.isGlobal && channel != client {
                guard let items = try? names(for: channel, updated: updated) else {
                    checkedAllNames = false
                    break
                }
                for item in items where unknown.contains(item.value) {
                    itemsByName[item.value, default: []].append(item)
                }
            }
        }
        func localized(_ input: String) -> String? {
            if !checkedAllNames && unknown.contains(input) { return nil }
            if let items = itemsByName[input], let first = items.first {
                guard let name = local[first.key], !name.isEmpty,
                    items.allSatisfy({ local[$0.key] == name })
                else { return nil }
                return name
            }
            if let name = local[input] { return name.isEmpty ? nil : name }
            return base[input] == nil ? input : nil
        }
        config.buy_first = buy_first.compactMap(localized)
        config.blacklist = blacklist.compactMap(localized)
        config.shopping = config.blacklist.count == blacklist.count
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
