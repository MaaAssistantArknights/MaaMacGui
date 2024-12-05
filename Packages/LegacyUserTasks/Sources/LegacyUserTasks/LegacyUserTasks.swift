//
//  LegacyUserTasks.swift
//  LegacyUserTasks
//
//  Created by hguandl on 2024/12/4.
//

import Foundation

@frozen public enum MAALegacyTask: Codable {
    case startup(LegacyStartupConfiguration)
    case closedown(LegacyClosedownConfiguration)
    case recruit(LegacyRecruitConfiguration)
    case infrast(LegacyInfrastConfiguration)
    case fight(LegacyFightConfiguration)
    case mall(LegacyMallConfiguration)
    case award(LegacyAwardConfiguration)
    case roguelike(LegacyRoguelikeConfiguration)
    case reclamation(LegacyReclamationConfiguration)
}

public func legacyTasks() throws -> [MAALegacyTask] {
    let legacyTasksURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first!
        .appendingPathComponent("UserTasks")
        .appendingPathExtension("plist")

    if !FileManager.default.fileExists(atPath: legacyTasksURL.path) {
        return []
    }

    let data = try Data(contentsOf: legacyTasksURL)
    let tasks = try PropertyListDecoder().decode(OrderedStore<MAALegacyTask>.self, from: data)

    try? FileManager.default.removeItem(at: legacyTasksURL)
    return tasks.values
}
