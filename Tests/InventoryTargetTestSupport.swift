import Foundation
protocol MAATaskConfiguration: Codable, Hashable, Sendable {}
extension MAATaskConfiguration {
    init() { self = try! JSONDecoder().decode(Self.self, from: Data("{}".utf8)) }
}
enum MAATaskType { case Fight; var description: String { "Fight" } }
enum MAATask { case fight(FightConfiguration) }
