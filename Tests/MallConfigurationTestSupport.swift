import Foundation

// Only app/Core types are stubbed; the real configuration protocol, channel enum,
// calendar, Mall configuration and JBird builder are compiled by the runner.
enum MAATaskType: CustomStringConvertible {
    // Match the production MaaCore enum case.
    // swift-format-ignore: AlwaysUseLowerCamelCase
    case Mall
    var description: String { "Mall" }
}

enum MAATask {
    case mall(MallConfiguration)
}

enum MallTestClock {
    static var dates: [Date] = []
    static var reads = 0

    static var now: Date {
        let value = dates[min(reads, dates.count - 1)]
        reads += 1
        return value
    }
}
