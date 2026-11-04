import Foundation

// Core linkage and unrelated task metadata are excluded; configuration,
// calendar, activity decoding and legacy migration compile from production.
protocol MAATaskConfiguration: Codable, Hashable, Sendable {
    associatedtype Params: Encodable
    var params: Params { get }
}
extension MAATaskConfiguration {
    init() { self = try! JSONDecoder().decode(Self.self, from: Data("{}".utf8)) }
}
enum MAATaskType {
    case Fight
    var description: String { "Fight" }
}
enum MAATask { case fight(FightConfiguration) }
