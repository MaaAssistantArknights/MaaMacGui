import Foundation

// Only task metadata dependencies are replaced. Production configuration,
// catalog loader and legacy migration implementations are compiled by the runner.
protocol MAATaskConfiguration: Codable, Hashable, Sendable {
    associatedtype Params: Encodable
    var params: Params { get }
}

extension MAATaskConfiguration {
    init() {
        self = try! JSONDecoder().decode(Self.self, from: Data("{}".utf8))
    }
}

enum MAATaskType {
    case Recruit
    var description: String { "Recruit" }
}

enum MAATask {
    case recruit(RecruitConfiguration)
}
