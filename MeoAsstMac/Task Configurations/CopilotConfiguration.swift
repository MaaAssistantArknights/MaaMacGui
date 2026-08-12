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
        let stage_name: String
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

@Observable final class CopilotContext {
    var config = CopilotConfiguration()

    struct ItemID: Hashable {
        let url: URL
        let isRaid: Bool?
    }

    var selection: ItemID? {
        didSet {
            guard oldValue != selection else {
                return
            }
            guard let url = selection?.url else {
                content = nil
                return
            }
            if url.isDirectory {
                if let set = CopilotSetData(atDirectory: url) {
                    content = .set(set)
                } else {
                    content = .directory
                }
            } else {
                if let copilot = MAACopilot(url: url) {
                    content = .copilot(copilot)
                } else {
                    content = .invalid
                }
            }
        }
    }

    var url: URL? {
        selection?.url
    }

    enum Content {
        case copilot(MAACopilot)
        case set(CopilotSetData)
        case directory
        case invalid
    }

    private(set) var content: Content?

    var isListMode = false

    struct CopilotSet {
        let kind: MAACopilot.Kind
        let data: CopilotSetData
    }

    private(set) var copilotSet: CopilotSet?

    struct ListItem: Identifiable {
        let url: URL
        let stageName: String
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
    func updateCopilotSet() {
        guard let url, case .set(let set) = content else {
            return
        }
        guard let (kind, list) = set.copilotList(at: url) else {
            return
        }

        self.copilotSet = .init(kind: kind, data: set)
        self.copilotList = list
    }
}

extension CopilotSetData {
    func copilotList(at url: URL) -> (MAACopilot.Kind, [CopilotContext.ListItem])? {
        guard url.isDirectory else { return nil }

        var copilotList = [CopilotContext.ListItem]()

        var lastCopilotKind: MAACopilot.Kind?

        for copilotID in copilot_ids {
            let url = url.appending(path: "\(copilotID).json")
            guard let copilot = MAACopilot(url: url) else { return nil }

            if lastCopilotKind == nil {
                lastCopilotKind = copilot.kind
            } else if lastCopilotKind != copilot.kind {
                print("Mixed copilot kind in list")
                return nil
            }

            let stageName = copilot.stage_name
            switch copilot.difficulty {
            case nil, 0:
                copilotList.append(.init(url: url, stageName: stageName, isOn: true))
            case 1:
                copilotList.append(.init(url: url, stageName: stageName, isRaid: false, isOn: true))
            case 2:
                copilotList.append(.init(url: url, stageName: stageName, isRaid: true, isOn: true))
            case 3:
                copilotList.append(.init(url: url, stageName: stageName, isRaid: false, isOn: true))
                copilotList.append(.init(url: url, stageName: stageName, isRaid: true, isOn: true))
            default:
                continue
            }
        }

        return (lastCopilotKind ?? .regular, copilotList)
    }
}

extension MAACopilot {
    enum Kind {
        case regular
        case sss
        case paradox
    }

    var kind: Kind {
        if type == "SSS" {
            return .sss
        }
        if stage_name.starts(with: "mem_") {
            return .paradox
        }
        return .regular
    }
}
