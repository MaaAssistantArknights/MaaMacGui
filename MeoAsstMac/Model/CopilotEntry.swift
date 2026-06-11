//
//  CopilotEntry.swift
//  MAA
//
//  Model for the Copilot List (作业集) feature: an ordered, persisted list of
//  copilot operations that run in sequence via the core's `copilot_list` param.
//

import Foundation

/// A single entry in the copilot list. Field names mirror the Windows persisted schema
/// (`name`/`file_path`/`copilot_id`/`is_raid`/`is_checked`) for cross-platform familiarity.
struct CopilotEntry: Codable, Identifiable, Equatable {
    var id = UUID()

    /// Stage code, used by the core for auto-navigation (e.g. "1-7", "main_01-07").
    var name: String

    /// Absolute path to the copilot JSON file.
    var filePath: String

    /// PRTS Plus id (0 for local files).
    var copilotId: Int

    /// Whether this stage should be run in raid (突袭) difficulty.
    var isRaid: Bool

    /// Whether this entry is selected for the next run.
    var isChecked: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case filePath = "file_path"
        case copilotId = "copilot_id"
        case isRaid = "is_raid"
        case isChecked = "is_checked"
    }

    init(
        name: String, filePath: String, copilotId: Int = 0, isRaid: Bool = false,
        isChecked: Bool = true
    ) {
        self.name = name
        self.filePath = filePath
        self.copilotId = copilotId
        self.isRaid = isRaid
        self.isChecked = isChecked
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.filePath = try container.decode(String.self, forKey: .filePath)
        self.copilotId = try container.decodeIfPresent(Int.self, forKey: .copilotId) ?? 0
        self.isRaid = try container.decodeIfPresent(Bool.self, forKey: .isRaid) ?? false
        self.isChecked = try container.decodeIfPresent(Bool.self, forKey: .isChecked) ?? true
    }
}

/// Global options applied to a whole copilot-list run, mirroring the Windows
/// `AsstCopilotTask` global flags.
struct CopilotListOptions: Codable, Equatable {
    var formation = true
    var addTrust = false
    var useSanityPotion = false

    /// Support unit usage: 0 = none, 1 = when needed, 3 = random.
    var supportUnitUsage = 0
}
