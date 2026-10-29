import Foundation

struct AchievementDefinition: Identifiable, Sendable {
    let id: String
    let metric: AchievementMetric
    let target: Int
    let groupID: String
    let hidden: Bool
    let conditionVersion: Int = 1
    var title: String { String(localized: String.LocalizationValue("Achievement.Title." + id)) }
    var condition: String { String(localized: String.LocalizationValue("Achievement.Condition." + id)) }

    static let all: [Self] = [
        .init(id: "FirstLaunch", metric: .firstLaunch, target: 1, groupID: "basic", hidden: false),
        .init(id: "SanitySpender1", metric: .battle, target: 10, groupID: "basic", hidden: false),
        .init(id: "SanitySpender2", metric: .battle, target: 100, groupID: "basic", hidden: false),
        .init(id: "SanitySpender3", metric: .battle, target: 1000, groupID: "basic", hidden: false),
        .init(id: "SanitySaver1", metric: .medicine, target: 1, groupID: "basic", hidden: false),
        .init(id: "SanitySaver2", metric: .medicine, target: 10, groupID: "basic", hidden: false),
        .init(id: "SanitySaver3", metric: .medicine, target: 50, groupID: "basic", hidden: false),
        .init(id: "SanityExpire", metric: .expiringBatch, target: 8, groupID: "basic", hidden: false),
        .init(id: "OverLimitAgent", metric: .runBattle, target: 100, groupID: "basic", hidden: true),
        .init(id: "RoguelikeGamePass1", metric: .roguePass, target: 1, groupID: "roguelike", hidden: false),
        .init(id: "RoguelikeGamePass2", metric: .roguePass, target: 5, groupID: "roguelike", hidden: false),
        .init(id: "RoguelikeGamePass3", metric: .roguePass, target: 10, groupID: "roguelike", hidden: false),
        .init(id: "RoguelikeN04", metric: .rogueDifficulty, target: 4, groupID: "roguelike", hidden: false),
        .init(id: "RoguelikeN08", metric: .rogueDifficulty, target: 8, groupID: "roguelike", hidden: false),
        .init(id: "RoguelikeN12", metric: .rogueDifficulty, target: 12, groupID: "roguelike", hidden: false),
        .init(id: "RoguelikeN15", metric: .rogueDifficulty, target: 15, groupID: "roguelike", hidden: false),
        .init(id: "RoguelikeRetreat", metric: .rogueRetreat, target: 100, groupID: "roguelike", hidden: false),
        .init(id: "RoguelikeGoldMax", metric: .rogueGold, target: 999, groupID: "roguelike", hidden: false),
        .init(id: "RecruitGambler", metric: .recruitRefresh, target: 50, groupID: "basic", hidden: false),
        .init(id: "ClueCollector", metric: .clueUse, target: 20, groupID: "basic", hidden: false),
        .init(id: "CluePhilosopher", metric: .clueUse, target: 50, groupID: "basic", hidden: false),
        .init(id: "ClueSharer", metric: .clueSend, target: 20, groupID: "basic", hidden: false),
        .init(id: "CluePhilanthropist", metric: .clueSend, target: 50, groupID: "basic", hidden: false),
        .init(id: "UseCopilot1", metric: .copilot, target: 1, groupID: "copilot", hidden: false),
        .init(id: "UseCopilot2", metric: .copilot, target: 10, groupID: "copilot", hidden: false),
        .init(id: "UseCopilot3", metric: .copilot, target: 100, groupID: "copilot", hidden: false),
        .init(id: "CopilotError", metric: .copilotError, target: 1, groupID: "copilot", hidden: false),
        .init(id: "MapOutdated", metric: .mapOutdated, target: 1, groupID: "copilot", hidden: true),
        .init(id: "Irreplaceable", metric: .missingFormation, target: 1, groupID: "copilot", hidden: true),
        .init(id: "TacticalRetreat", metric: .manualStop, target: 1, groupID: "features", hidden: false),
        .init(id: "ScheduleMaster1", metric: .scheduledStart, target: 1, groupID: "features", hidden: false),
        .init(id: "ScheduleMaster2", metric: .scheduledStart, target: 100, groupID: "features", hidden: false),
        .init(id: "PeekScreen", metric: .peep, target: 1, groupID: "features", hidden: true),
        .init(id: "HotkeyMagician", metric: .hotkey, target: 1, groupID: "features", hidden: false),
        .init(id: "StartupBoot", metric: .startup, target: 1, groupID: "features", hidden: false),
        .init(id: "AchievementObserver", metric: .achievementView, target: 1, groupID: "features", hidden: false),
        .init(id: "SnapshotChallenge1", metric: .snapshot1, target: 1, groupID: "features", hidden: true),
        .init(id: "SnapshotChallenge2", metric: .snapshot2, target: 1, groupID: "features", hidden: true),
        .init(id: "SnapshotChallenge3", metric: .snapshot3, target: 1, groupID: "features", hidden: false),
        .init(id: "SnapshotChallenge4", metric: .snapshot4, target: 1, groupID: "features", hidden: false),
        .init(id: "SnapshotChallenge5", metric: .snapshot5, target: 1, groupID: "features", hidden: false),
        .init(id: "SnapshotChallenge6", metric: .snapshot6, target: 1, groupID: "features", hidden: true),
        .init(id: "MosquitoLeg", metric: .creditFight, target: 5, groupID: "features", hidden: false),
        .init(id: "RecruitNoSixStar", metric: .recruitNoSix, target: 500, groupID: "basic", hidden: false),
        .init(id: "RecruitNoSixStarStreak", metric: .recruitNoSixStreak, target: 500, groupID: "basic", hidden: true),
    ]
}
