//
//  CopilotConfiguration.swift
//  MAA
//
//  Created by hguandl on 17/4/2023.
//

import Foundation
import Observation

struct CopilotConfiguration: Codable, Hashable {
    var enable = true

    var filename: String?

    struct CopilotItem: Codable, Hashable {
        let filename: String
        let nav_name_override: String?
        let is_raid: Bool
    }

    var copilot_list = [CopilotItem]()

    var loop_times = 1

    var use_sanity_potion = false

    var formation = false
    var formation_index = 0

    struct UserUnit: Codable, Hashable {
        let name: String
        let skill: Int
    }

    var user_additional = [UserUnit]()

    var add_trust = false
    var ignore_requirements = false

    enum SupportUnitUsage: Int, CaseIterable, Codable {
        /// 不加助战干员
        case none = 0
        /// 如果仅缺一名干员则尝试补助战
        case whenNeeded = 1
        /// 如果仅缺一名干员则尝试补助战，如无缺失则随机加一个助战干员
        case random = 3
        /// 如果仅缺一名干员则尝试补助战，如无缺失则使用指定助战干员
        case specific = 2
    }

    var support_unit_usage = SupportUnitUsage.none
    var support_unit_name = ""
}

extension CopilotConfiguration.SupportUnitUsage: Identifiable {
    var id: Int {
        rawValue
    }
}

extension CopilotConfiguration.SupportUnitUsage: CustomStringConvertible {
    var description: String {
        switch self {
        case .none:
            return String(localized: "不借", comment: "")
        case .whenNeeded:
            return String(localized: "补漏", comment: "")
        case .specific:
            return String(localized: "指定", comment: "")
        case .random:
            return String(localized: "随机", comment: "")
        }
    }
}

struct VideoRecognitionConfiguration: Codable {
    var enable = true
    var filename: String

    var params: String? {
        try? jsonString()
    }
}

enum CopilotCategory: String, CaseIterable {
    case bundled
    case external
    case list
}

extension CopilotCategory {
    static let userDefaultsKey = "CopilotContentCategory"

    static func userDefaultsValue(defaults: UserDefaults = .standard) -> Self {
        let rawValue = defaults.string(forKey: userDefaultsKey)
        if let rawValue {
            return .init(rawValue: rawValue) ?? .bundled
        } else {
            return .bundled
        }
    }

    func setUserDefaults(defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.userDefaultsKey)
    }
}

@Observable final class CopilotContext {
    var config = CopilotConfiguration()

    var category: CopilotCategory {
        get {
            access(keyPath: \.category)
            return .userDefaultsValue()
        }
        set {
            withMutation(keyPath: \.category) {
                newValue.setUserDefaults()
            }
        }
    }

    @ObservationIgnored private var categoryObserver: UserDefaultsObserver<String>?

    init() {
        categoryObserver = UserDefaults.standard.observeKey(CopilotCategory.userDefaultsKey) { [weak self] _ in
            self?.withMutation(keyPath: \.category) {}
        }
    }

    deinit {
        if let categoryObserver {
            UserDefaults.standard.removeObserver(categoryObserver, forKeyPath: CopilotCategory.userDefaultsKey)
        }
    }

    struct ItemID: Hashable {
        let url: URL
        let isRaid: Bool?
    }

    @MainActor var selection: ItemID? {
        didSet {
            guard oldValue != selection else {
                return
            }
            guard let url = selection?.url else {
                content = nil
                return
            }
            content = .pending
            Task {
                content = await Content(url: url)
            }
        }
    }

    enum Content: Equatable {
        case pending
        case copilot(URL, MAACopilot.Kind, MAACopilot)
        case set(URL, CopilotSetData)
        case directory
        case invalid
    }

    private(set) var content: Content?

    struct CopilotSet {
        let kind: MAACopilot.Kind
        let data: CopilotSetData
    }

    private(set) var copilotSet: CopilotSet?

    struct ListItem: Identifiable {
        let url: URL
        let stageCode: String
        var isRaid: Bool?

        var isOn = false

        var id: ItemID {
            .init(url: url, isRaid: isRaid)
        }
    }

    var copilotList = [ListItem]() {
        didSet {
            if copilotList.isEmpty {
                copilotSet = nil
            }
        }
    }
}

extension CopilotContext {
    nonisolated(nonsending) func updateSet(at url: URL, set: CopilotSetData) async {
        guard let (kind, list) = await set.copilotList(at: url) else {
            return
        }

        self.copilotSet = .init(kind: kind, data: set)
        self.copilotList = list
    }

    nonisolated(nonsending) func updateSet(at url: URL) async {
        guard let set = CopilotSetData(atDirectory: url) else {
            return
        }
        await updateSet(at: url, set: set)
    }
}

extension CopilotContext.Content {
    @concurrent init(url: URL) async {
        if url.isDirectory {
            if let set = CopilotSetData(atDirectory: url) {
                self = .set(url, set)
            } else {
                self = .directory
            }
        } else {
            if let copilot = MAACopilot(url: url) {
                let kind = await copilot.kind
                self = .copilot(url, kind, copilot)
            } else {
                self = .invalid
            }
        }
    }
}

extension CopilotSetData {
    func copilotList(at url: URL) async -> (MAACopilot.Kind, [CopilotContext.ListItem])? {
        guard url.isDirectory else { return nil }

        var copilotList = [CopilotContext.ListItem]()

        var lastCopilotKind: MAACopilot.Kind?

        for copilotID in copilot_ids {
            let url = url.appending(path: "\(copilotID).json")
            guard let copilot = MAACopilot(url: url),
                let code = await MAAProvider.shared.mapLevelCode(matching: copilot.stage_name)
            else {
                return nil
            }

            let kind = copilot.kind(code: code)
            if lastCopilotKind == nil {
                lastCopilotKind = kind
            } else if lastCopilotKind != kind {
                print("Mixed copilot kind in list")
                return nil
            }

            switch copilot.difficulty {
            case nil, 0:
                copilotList.append(.init(url: url, stageCode: code, isOn: true))
            case 1:
                copilotList.append(.init(url: url, stageCode: code, isRaid: false, isOn: true))
            case 2:
                copilotList.append(.init(url: url, stageCode: code, isRaid: true, isOn: true))
            case 3:
                copilotList.append(.init(url: url, stageCode: code, isRaid: false, isOn: true))
                copilotList.append(.init(url: url, stageCode: code, isRaid: true, isOn: true))
            default:
                continue
            }
        }

        return (lastCopilotKind ?? .regular, copilotList)
    }
}

extension MAACopilot {
    enum Kind: Hashable {
        case regular
        case sss
        case paradox
    }

    func kind(code: String) -> Kind {
        if type == "SSS" {
            return .sss
        }
        if code.starts(with: "mem_") {
            return .paradox
        }
        return .regular
    }

    var kind: Kind {
        get async {
            if type == "SSS" {
                return .sss
            }
            let code = await MAAProvider.shared.mapLevelCode(matching: stage_name)
            if let code, code.starts(with: "mem_") {
                return .paradox
            }
            return .regular
        }
    }
}
