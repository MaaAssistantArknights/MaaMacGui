import Foundation

@main
struct MallConfigurationTests {
    static func main() throws {
        let formatter = ISO8601DateFormatter()
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            guard condition else {
                fputs("FAIL: \(message)\n", stderr)
                exit(1)
            }
            checks += 1
        }

        for channel in MAAClientChannel.allCases {
            let reset = channel.calendar.nextReset(after: formatter.date(from: "2026-01-15T00:00:00Z")!)
            let before = reset.addingTimeInterval(-0.001)
            let after = reset.addingTimeInterval(0.001)
            for (creditEnabled, visitsEnabled) in [(true, true), (true, false), (false, true), (false, false)] {
                for (fightCompleted, visitLimited) in [(true, true), (true, false), (false, true), (false, false)] {
                    for now in [before, after] {
                        var config = try JSONDecoder().decode(MallConfiguration.self, from: Data("{}".utf8))
                        config.clientChannel = channel
                        config.creditFight = creditEnabled
                        config.visitFriends = visitsEnabled
                        config.shopping = false
                        config.formationIndex = 3
                        config.creditFightDate = fightCompleted ? before : .distantPast
                        config.friendVisitDate = visitLimited ? before : .distantPast

                        // Parameter generation must snapshot the clock exactly once. Rig the clock
                        // so the single read yields `now`, and keep the trailing entries as trap
                        // dates: any extra read would cross the reset and fail the checks below.
                        MallTestClock.dates = [now, now, after]
                        MallTestClock.reads = 0
                        let data = try JSONEncoder().encode(config.params)
                        let params = try JSONSerialization.jsonObject(with: data) as! [String: Any]
                        let expectedFight = creditEnabled && (!fightCompleted || now == after)
                        let expectedVisit = visitsEnabled && (!visitLimited || now == after)
                        let context =
                            "\(channel.rawValue) credit=\(creditEnabled)/\(fightCompleted) visits=\(visitsEnabled)/\(visitLimited) now=\(now)"
                        check(params["credit_fight"] as? Bool == expectedFight, "\(context): credit fight")
                        check(params["visit_friends"] as? Bool == expectedVisit, "\(context): friend visit")
                        check(
                            (params["formation_index"] != nil) == expectedFight,
                            "\(context): formation must be present exactly when a fight is scheduled")
                        if expectedFight {
                            check(params["formation_index"] as? Int == 3, "\(context): selected formation")
                        }
                        check(params["shopping"] as? Bool == false, "\(context): shopping changed")
                        check(MallTestClock.reads == 1, "\(context): parameter generation must read the clock once")
                    }
                }
            }
        }
        // MARK: Batch daily admission (same-batch dedup)

        func makeMall(
            creditFight: Bool = true,
            visitFriends: Bool = true,
            creditFightDate: Date = .distantPast,
            friendVisitDate: Date = .distantPast
        ) throws -> MallConfiguration {
            var config = try JSONDecoder().decode(MallConfiguration.self, from: Data("{}".utf8))
            config.creditFight = creditFight
            config.visitFriends = visitFriends
            config.creditFightDate = creditFightDate
            config.friendVisitDate = friendVisitDate
            return config
        }

        let unmarked = MallConfiguration.BatchDailyAdmission(creditFightMarkedDate: nil, friendVisitMarkedDate: nil)

        for channel in MAAClientChannel.allCases {
            let calendar = channel.calendar
            let reset = calendar.nextReset(after: formatter.date(from: "2026-01-15T00:00:00Z")!)
            let before = reset.addingTimeInterval(-0.001)
            let after = reset.addingTimeInterval(0.001)
            let context = channel.rawValue

            let eligibleA = try makeMall()
            let eligibleB = try makeMall()
            let eligibleC = try makeMall()

            // 两个具备资格的 Mall：仅首个放行，次个两项都预标记为快照日。
            let twoEligible = MallConfiguration.batchDailyAdmissions(
                of: [(enabled: true, config: eligibleA), (enabled: true, config: eligibleB)],
                snapshotDate: before, calendar: calendar)
            check(twoEligible[0] == unmarked, "\(context): first eligible Mall must not be pre-marked")
            check(
                twoEligible[1] == .init(creditFightMarkedDate: before, friendVisitMarkedDate: before),
                "\(context): second eligible Mall must be pre-marked with the snapshot date")

            // 禁用任务不具备资格，不占放行名额。
            let disabledFirst = MallConfiguration.batchDailyAdmissions(
                of: [(enabled: false, config: eligibleA), (enabled: true, config: eligibleB)],
                snapshotDate: before, calendar: calendar)
            check(disabledFirst[0] == unmarked, "\(context): disabled Mall must not be pre-marked")
            check(
                disabledFirst[1] == unmarked,
                "\(context): disabled Mall must not consume the daily admission")

            // 当日已完成者不具备资格，不占放行名额。
            let doneToday = try makeMall(creditFightDate: before, friendVisitDate: before)
            let doneTodayFirst = MallConfiguration.batchDailyAdmissions(
                of: [(enabled: true, config: doneToday), (enabled: true, config: eligibleB)],
                snapshotDate: before, calendar: calendar)
            check(doneTodayFirst[0] == unmarked, "\(context): already-done Mall must not be pre-marked")
            check(
                doneTodayFirst[1] == unmarked,
                "\(context): already-done Mall must not consume the daily admission")

            // 三个具备资格的 Mall：仅首个放行，其余两个都预标记。
            let threeEligible = MallConfiguration.batchDailyAdmissions(
                of: [
                    (enabled: true, config: eligibleA), (enabled: true, config: eligibleB),
                    (enabled: true, config: eligibleC),
                ], snapshotDate: before, calendar: calendar)
            check(threeEligible[0] == unmarked, "\(context): first of three Malls must not be pre-marked")
            check(
                threeEligible[1] == .init(creditFightMarkedDate: before, friendVisitMarkedDate: before),
                "\(context): second of three Malls must be pre-marked")
            check(
                threeEligible[2] == .init(creditFightMarkedDate: before, friendVisitMarkedDate: before),
                "\(context): third of three Malls must be pre-marked")

            // 信用战与好友访问各自独立放行，关闭的开关单项不占名额。
            let fightOnly = try makeMall(visitFriends: false)
            let visitOnly = try makeMall(creditFight: false)
            let independent = MallConfiguration.batchDailyAdmissions(
                of: [(enabled: true, config: fightOnly), (enabled: true, config: visitOnly)],
                snapshotDate: before, calendar: calendar)
            check(
                independent[0] == unmarked && independent[1] == unmarked,
                "\(context): credit fight and friend visit admissions must be independent")

            // 预标记日期在快照时刻即被参数闸门识别为同日（判定与消费一致）。
            var premarked = eligibleB
            premarked.creditFightDate = twoEligible[1].creditFightMarkedDate!
            premarked.friendVisitDate = twoEligible[1].friendVisitMarkedDate!
            MallTestClock.dates = [before, before, after]
            MallTestClock.reads = 0
            let premarkedParams =
                try JSONSerialization.jsonObject(with: JSONEncoder().encode(premarked.params)) as! [String: Any]
            check(premarkedParams["credit_fight"] as? Bool == false, "\(context): pre-marked date must suppress credit fight")
            check(premarkedParams["visit_friends"] as? Bool == false, "\(context): pre-marked date must suppress friend visit")
            check(MallTestClock.reads == 1, "\(context): unmaterialized parameter generation must read the clock once")

            // 快照日落在重置点之后：新游戏日的"当日已完成"同样不占名额。
            let newDayDone = try makeMall(creditFightDate: after, friendVisitDate: after)
            let newDayBatch = MallConfiguration.batchDailyAdmissions(
                of: [(enabled: true, config: newDayDone), (enabled: true, config: eligibleB)],
                snapshotDate: after, calendar: calendar)
            check(
                newDayBatch[0] == unmarked && newDayBatch[1] == unmarked,
                "\(context): completion on the new game day must not consume the admission")
        }

        // MARK: Materialized batch snapshot across the append window

        for channel in MAAClientChannel.allCases {
            let calendar = channel.calendar
            let reset = calendar.nextReset(after: formatter.date(from: "2026-01-15T00:00:00Z")!)
            let before = reset.addingTimeInterval(-0.001)
            let after = reset.addingTimeInterval(0.001)
            let context = channel.rawValue

            // 预标记 + 物化快照：注入后时钟跨过 04:00（如 ensureHandle 装载框架的 await 窗口），
            // 参数闸门仍按快照日判定，同批去重不失效。
            var premarkedAgain = try makeMall()
            premarkedAgain.creditFightDate = before
            premarkedAgain.friendVisitDate = before
            premarkedAgain.batchSnapshotDate = before
            MallTestClock.dates = [after]
            MallTestClock.reads = 0
            let premarkedAgainParams =
                try JSONSerialization.jsonObject(
                    with: JSONEncoder().encode(premarkedAgain.params)) as! [String: Any]
            check(
                premarkedAgainParams["credit_fight"] as? Bool == false,
                "\(context): pre-marked Mall must stay skipped after the clock crosses the reset")
            check(
                premarkedAgainParams["visit_friends"] as? Bool == false,
                "\(context): pre-marked visit must stay skipped after the clock crosses the reset")
            check(
                MallTestClock.reads == 0,
                "\(context): materialized snapshot must remove clock reads from parameter generation")

            // 放行名额同样在快照时刻锁定：append 前跨日不丢失本批放行。
            var admittedAgain = try makeMall()
            admittedAgain.batchSnapshotDate = before
            MallTestClock.dates = [after]
            MallTestClock.reads = 0
            let admittedAgainParams =
                try JSONSerialization.jsonObject(
                    with: JSONEncoder().encode(admittedAgain.params)) as! [String: Any]
            check(
                admittedAgainParams["credit_fight"] as? Bool == true,
                "\(context): admitted Mall must keep its slot after the clock crosses the reset")
            check(
                admittedAgainParams["visit_friends"] as? Bool == true,
                "\(context): admitted visit must keep its slot after the clock crosses the reset")
            check(
                admittedAgainParams["formation_index"] as? Int == 0,
                "\(context): admitted Mall must schedule the selected formation")
            check(
                MallTestClock.reads == 0,
                "\(context): admitted parameter generation must not read the clock")

            // 物化快照不参与持久化：编码-解码往返后必须归 nil，其余字段不受影响。
            var encoded = try makeMall()
            encoded.batchSnapshotDate = before
            encoded.creditFightDate = before
            let roundTrip = try JSONDecoder().decode(
                MallConfiguration.self, from: JSONEncoder().encode(encoded))
            check(roundTrip.batchSnapshotDate == nil, "\(context): batch snapshot must not be persisted")
            check(roundTrip.creditFightDate == before, "\(context): persisted dates must survive the round trip")
        }

        // MARK: Conservative daily write-back date

        for channel in MAAClientChannel.allCases {
            let calendar = channel.calendar
            let reset = calendar.nextReset(after: formatter.date(from: "2026-01-15T00:00:00Z")!)
            let before = reset.addingTimeInterval(-0.001)
            let after = reset.addingTimeInterval(0.001)
            let midDay = reset.addingTimeInterval(-3600)
            let context = channel.rawValue

            check(
                MallConfiguration.dailyWriteBackDate(now: midDay, roundStart: nil, calendar: calendar) == midDay,
                "\(context): missing round anchor must fall back to the processing time")
            check(
                MallConfiguration.dailyWriteBackDate(now: midDay, roundStart: before, calendar: calendar)
                    == midDay,
                "\(context): same game day must write back the processing time")
            check(
                MallConfiguration.dailyWriteBackDate(now: after, roundStart: before, calendar: calendar)
                    == before,
                "\(context): crossing the reset must write back the round start")
            check(
                MallConfiguration.dailyWriteBackDate(
                    now: after.addingTimeInterval(60), roundStart: after, calendar: calendar
                ) == after.addingTimeInterval(60),
                "\(context): same new game day must write back the processing time")
        }

        print("Passed \(checks) Mall configuration checks across all six channels")
    }
}
