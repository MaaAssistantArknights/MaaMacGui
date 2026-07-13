import XCTest

final class StageCatalogTests: XCTestCase {
    func testBuiltInWeeklySchedules() throws {
        let catalog = StageCatalog()
        let stages = Dictionary(uniqueKeysWithValues: catalog.stages(for: .official).map { ($0.id, $0) })
        let expected: [String: Set<Int>] = [
            "CE-6": [1, 3, 5, 7],
            "AP-5": [1, 2, 5, 7],
            "CA-5": [1, 3, 4, 6],
            "SK-5": [2, 4, 6, 7],
            "PR-A-1": [1, 2, 5, 6],
            "PR-A-2": [1, 2, 5, 6],
            "PR-B-1": [2, 3, 6, 7],
            "PR-B-2": [2, 3, 6, 7],
            "PR-C-1": [1, 4, 5, 7],
            "PR-C-2": [1, 4, 5, 7],
            "PR-D-1": [1, 3, 4, 7],
            "PR-D-2": [1, 3, 4, 7],
        ]

        for (stage, weekdays) in expected {
            XCTAssertEqual(try XCTUnwrap(stages[stage]).openWeekdays, weekdays, stage)
        }
        XCTAssertNil(try XCTUnwrap(stages["LS-6"]).openWeekdays)
    }

    func testServerDayChangesAtFourForEveryTimezone() throws {
        let catalog = StageCatalog()
        for (server, offset) in [(StageServer.official, 8), (.yoStarJP, 9), (.yoStarEN, -7)] {
            let before = try date("2026/07/13 03:59:59", offset: offset)
            let boundary = try date("2026/07/13 04:00:00", offset: offset)
            XCTAssertEqual(catalog.serverWeekday(for: server, now: before), 1)
            XCTAssertEqual(catalog.serverWeekday(for: server, now: boundary), 2)
        }
    }

    func testResourceCollectionOverridesWeeklyScheduleInclusively() throws {
        let catalog = try StageCatalog(data: Data(resourceCollectionJSON.utf8))
        let ap = try XCTUnwrap(catalog.stages(for: .official).first { $0.id == "AP-5" })
        let before = try date("2026/07/13 03:59:59", offset: 8)
        let start = try date("2026/07/13 04:00:00", offset: 8)
        let expire = try date("2026/07/14 03:59:59", offset: 8)
        let after = try date("2026/07/14 04:00:00", offset: 8)

        XCTAssertEqual(catalog.availability(of: ap, server: .official, now: before, coreVersion: nil), .open)
        XCTAssertEqual(catalog.availability(of: ap, server: .official, now: start, coreVersion: nil), .open)
        XCTAssertEqual(catalog.availability(of: ap, server: .official, now: expire, coreVersion: nil), .open)
        XCTAssertEqual(
            catalog.availability(of: ap, server: .official, now: after, coreVersion: nil),
            .closedForWeeklySchedule)
    }

    func testBilibiliUsesOfficialActivities() throws {
        let catalog = try StageCatalog(data: Data(sideStoryJSON.utf8))
        XCTAssertTrue(catalog.stages(for: .bilibili).contains { $0.id == "EV-8" })
    }

    func testSideStoryActivityWindowAndMinimumVersion() throws {
        let catalog = try StageCatalog(data: Data(sideStoryJSON.utf8))
        let stage = try XCTUnwrap(catalog.stages(for: .official).first { $0.id == "EV-8" })
        let before = try date("2026/07/12 15:59:59", offset: 8)
        let start = try date("2026/07/12 16:00:00", offset: 8)
        let expire = try date("2026/07/20 03:59:59", offset: 8)
        let after = try date("2026/07/20 04:00:00", offset: 8)

        XCTAssertEqual(
            catalog.availability(of: stage, server: .official, now: before, coreVersion: "v6.12.0"),
            .activityNotStarted)
        XCTAssertEqual(
            catalog.availability(of: stage, server: .official, now: start, coreVersion: "v6.11.9"),
            .unsupportedCoreVersion(required: "v6.12.0-beta.2"))
        XCTAssertEqual(
            catalog.availability(of: stage, server: .official, now: start, coreVersion: "v6.12.0-beta.1"),
            .unsupportedCoreVersion(required: "v6.12.0-beta.2"))
        XCTAssertEqual(
            catalog.availability(of: stage, server: .official, now: start, coreVersion: "v6.12.0"), .open)
        XCTAssertEqual(
            catalog.availability(of: stage, server: .official, now: start, coreVersion: "DEBUG_VERSION"), .open)
        XCTAssertEqual(
            catalog.availability(of: stage, server: .official, now: expire, coreVersion: "v6.12.0"), .open)
        XCTAssertEqual(
            catalog.availability(of: stage, server: .official, now: after, coreVersion: "v6.12.0"),
            .activityExpired)
    }

    func testMalformedActivityGroupDoesNotDiscardValidGroup() throws {
        let json = sideStoryJSON.replacingOccurrences(
            of: "\"sideStoryStage\": {",
            with: "\"sideStoryStage\": { \"Broken\": 42,")
        let catalog = try StageCatalog(data: Data(json.utf8))
        XCTAssertTrue(catalog.stages(for: .official).contains { $0.id == "EV-8" })
    }

    func testStageLevelMinimumVersionOverridesGroup() throws {
        let catalog = try StageCatalog(data: Data(sideStoryJSON.utf8))
        let stage = try XCTUnwrap(catalog.stages(for: .official).first { $0.id == "EV-7" })
        let now = try date("2026/07/22 12:00:00", offset: 8)
        XCTAssertEqual(
            catalog.availability(of: stage, server: .official, now: now, coreVersion: "v6.12.0"),
            .unsupportedCoreVersion(required: "v6.13.0"))
    }

    func testStageLevelActivityOverridesGroupActivity() throws {
        let catalog = try StageCatalog(data: Data(sideStoryJSON.utf8))
        let stage = try XCTUnwrap(catalog.stages(for: .official).first { $0.id == "EV-7" })
        let afterGroupExpired = try date("2026/07/22 12:00:00", offset: 8)

        XCTAssertEqual(
            catalog.availability(of: stage, server: .official, now: afterGroupExpired, coreVersion: "v6.13.0"),
            .open)
        XCTAssertEqual(stage.activityName, "Event Rerun")
        XCTAssertEqual(stage.activity?.expire, try date("2026/07/30 03:59:59", offset: 8))
    }

    func testUnavailableKnownStageIsNormalizedButCustomStageIsPreserved() throws {
        let catalog = StageCatalog()
        let tuesday = try date("2026/07/14 12:00:00", offset: 8)

        XCTAssertEqual(
            catalog.normalizedStageID("AP-5", server: .official, now: tuesday, coreVersion: nil), "")
        XCTAssertEqual(
            catalog.normalizedStageID("CE-6", server: .official, now: tuesday, coreVersion: nil), "CE-6")
        XCTAssertEqual(
            catalog.normalizedStageID("AveMujica-8", server: .official, now: tuesday, coreVersion: nil),
            "AveMujica-8")
    }

    func testChipStageDisplayNamesDescribeProfessions() {
        XCTAssertEqual(StageCatalog.builtInDisplayName(for: "PR-A-1"), "奶/盾芯片")
        XCTAssertEqual(StageCatalog.builtInDisplayName(for: "PR-B-2"), "术/狙芯片组")
        XCTAssertEqual(StageCatalog.builtInDisplayName(for: "PR-C-1"), "先/辅芯片")
        XCTAssertEqual(StageCatalog.builtInDisplayName(for: "PR-D-2"), "近/特芯片组")
    }

    func testTodaySummaryUsesServerDayAndCombinesChipStages() throws {
        let catalog = StageCatalog()
        let monday = try date("2026/07/13 12:00:00", offset: 8)
        let summary = catalog.todaySummary(for: .official, now: monday, coreVersion: nil)

        XCTAssertEqual(
            summary.localizedTipKeys,
            [
                "周一了，可以打剿灭了~",
                "AP-5: 红票",
                "LS-6: 经验",
                "SK-5: 碳",
                "PR-A-1/2: 奶/盾芯片",
                "PR-B-1/2: 术/狙芯片",
            ])
    }

    func testTodaySummaryDeduplicatesActivityName() throws {
        let catalog = try StageCatalog(data: Data(sideStoryJSON.utf8))
        let now = try date("2026/07/13 12:00:00", offset: 8)
        let summary = catalog.todaySummary(for: .official, now: now, coreVersion: "v6.13.0")

        XCTAssertEqual(summary.activities.count, 1)
        XCTAssertEqual(summary.activities.first?.name, "Event Name")
    }

    private func date(_ value: String, offset: Int) throws -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: offset * 3600)
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return try XCTUnwrap(formatter.date(from: value))
    }

    private var resourceCollectionJSON: String {
        """
        {
          "Official": {
            "resourceCollection": {
              "UtcStartTime": "2026/07/13 04:00:00",
              "UtcExpireTime": "2026/07/14 03:59:59",
              "TimeZone": 8,
              "IsResourceCollection": true
            }
          }
        }
        """
    }

    private var sideStoryJSON: String {
        """
        {
          "Official": {
            "sideStoryStage": {
              "Event": {
                "MinimumRequired": "v6.10.0",
                "Activity": {
                  "StageName": "Event Name",
                  "UtcStartTime": "2026/07/12 16:00:00",
                  "UtcExpireTime": "2026/07/20 03:59:59",
                  "TimeZone": 8
                },
                "Stages": [
                  { "Display": "Event 8", "Value": "EV-8", "MinimumRequired": "v6.12.0-beta.2" },
                  {
                    "Display": "Event 7",
                    "Value": "EV-7",
                    "MinimumRequired": "v6.13.0",
                    "Activity": {
                      "StageName": "Event Rerun",
                      "UtcStartTime": "2026/07/21 16:00:00",
                      "UtcExpireTime": "2026/07/30 03:59:59",
                      "TimeZone": 8
                    }
                  }
                ]
              }
            }
          }
        }
        """
    }
}
