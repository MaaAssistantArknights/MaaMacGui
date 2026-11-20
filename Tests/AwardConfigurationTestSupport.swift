import Foundation

// Only task metadata dependencies are replaced; the configuration and legacy
// migration under test are compiled from production sources by the runner.
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
    case Award
    var description: String { "Award" }
}

enum MAATask {
    case award(AwardConfiguration)
}
