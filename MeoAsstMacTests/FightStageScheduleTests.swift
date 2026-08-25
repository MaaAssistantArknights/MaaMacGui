import XCTest

final class FightStageScheduleTests: XCTestCase {
    private let schedule = FightStageSchedule()

    func testSelectsFirstOpenStage() throws {
        let monday = try date("2026-08-24 12:00:00", timeZone: "Asia/Shanghai")
        XCTAssertEqual(
            schedule.firstOpenStage(
                in: ["CE-6", "1-7", "AP-5"],
                server: .official,
                activities: nil,
                at: monday),
            "1-7")
    }

    func testReturnsNilWhenEveryStageIsClosed() throws {
        let monday = try date("2026-08-24 12:00:00", timeZone: "Asia/Shanghai")
        XCTAssertNil(
            schedule.firstOpenStage(
                in: ["CE-6", "CA-5"],
                server: .official,
                activities: nil,
                at: monday))
    }

    func testResourceCollectionOpensWeeklyStages() throws {
        let monday = try date("2026-08-24 12:00:00", timeZone: "Asia/Shanghai")
        let activities = FightStageSchedule.ActivityData(
            resourceCollection: .init(
                start: monday.addingTimeInterval(-60),
                expire: monday.addingTimeInterval(60)))

        XCTAssertTrue(schedule.isOpen("CE-6", server: .official, activities: activities, at: monday))
    }

    func testActivityStageUsesItsWindow() throws {
        let now = try date("2026-08-24 12:00:00", timeZone: "Asia/Shanghai")
        let activities = FightStageSchedule.ActivityData(
            stageWindows: [
                "AT-8": .init(
                    start: now.addingTimeInterval(-60),
                    expire: now.addingTimeInterval(60)),
                "TO-9": .init(
                    start: now.addingTimeInterval(-120),
                    expire: now.addingTimeInterval(-60)),
            ])

        XCTAssertTrue(schedule.isOpen("AT-8", server: .official, activities: activities, at: now))
        XCTAssertFalse(schedule.isOpen("TO-9", server: .official, activities: activities, at: now))
    }

    func testServerDayChangesAtFour() throws {
        let servers: [(FightStageSchedule.Server, String)] = [
            (.official, "Asia/Shanghai"),
            (.yoStarEN, "America/Los_Angeles"),
            (.yoStarJP, "Asia/Tokyo"),
            (.yoStarKR, "Asia/Seoul"),
            (.txwy, "Asia/Taipei"),
        ]
        for (server, timeZone) in servers {
            let before = try date("2026-08-24 03:59:59", timeZone: timeZone)
            let boundary = try date("2026-08-24 04:00:00", timeZone: timeZone)

            XCTAssertEqual(schedule.serverWeekday(server, at: before), 1)
            XCTAssertEqual(schedule.serverWeekday(server, at: boundary), 2)
        }
    }

    func testPermanentStageBlocksFollowingStages() {
        XCTAssertTrue(schedule.blocksFollowingStages("1-7", activities: nil))
        XCTAssertTrue(schedule.blocksFollowingStages("Annihilation", activities: nil))
        XCTAssertFalse(schedule.blocksFollowingStages("CE-6", activities: nil))
    }

    private func date(_ value: String, timeZone: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = try XCTUnwrap(TimeZone(identifier: timeZone))
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return try XCTUnwrap(formatter.date(from: value))
    }
}
