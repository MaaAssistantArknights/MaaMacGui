import Foundation

@main
struct HGCalendarTests {
    static func main() {
        let formatter = ISO8601DateFormatter()
        func date(_ value: String) -> Date { formatter.date(from: value)! }
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }

        // Server time is fixed UTC-7, including Pacific standard time.
        // Official winter schedules: https://www.arknights.global/news/2116
        // https://www.arknights.global/news/2371
        // Include both sides of the US daylight-saving transitions.
        for day in ["2026-01-15", "2026-03-08", "2026-07-15", "2026-11-01", "2026-12-25"] {
            for channel in MAAClientChannel.allCases {
                let hour: String
                let offset: Int
                switch channel {
                case .Official, .Bilibili, .txwy:
                    hour = "20"
                    offset = 8
                case .YoStarEN:
                    hour = "11"
                    offset = -7
                case .YoStarJP, .YoStarKR:
                    hour = "19"
                    offset = 9
                }
                let reset = date("\(day)T\(hour):00:00Z")
                let before = reset.addingTimeInterval(-1)
                let calendar = channel.calendar
                check(
                    calendar.calendar.timeZone.secondsFromGMT(for: reset) == offset * 3600,
                    "\(channel.rawValue) \(day): server offset changed")
                check(
                    calendar.isDate(before.addingTimeInterval(-3600), inSameDayAs: before),
                    "\(channel.rawValue) \(day): reset occurred too early")
                check(
                    !calendar.isDate(before, inSameDayAs: reset),
                    "\(channel.rawValue) \(day): expected a new game day at 04:00 server time")
                check(
                    calendar.isDate(reset, inSameDayAs: reset.addingTimeInterval(3600)),
                    "\(channel.rawValue) \(day): reset occurred too late")
                check(
                    calendar.nextReset(after: before) == reset,
                    "\(channel.rawValue) \(day): next reset mismatch")
                check(
                    calendar.nextReset(after: reset) == reset.addingTimeInterval(86400),
                    "\(channel.rawValue) \(day): game day must remain 24 hours")
            }
        }
        print("Passed \(checks) game-calendar checks across all six channels")
    }
}
