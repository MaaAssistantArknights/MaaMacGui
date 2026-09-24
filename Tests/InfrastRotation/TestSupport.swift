import SwiftUI

enum MAATaskType { case Infrast; var description: String { "基建换班" } }
protocol MAATaskConfiguration: Codable, Hashable, Sendable {}
extension MAATaskConfiguration {
    init() { self = try! JSONDecoder().decode(Self.self, from: Data("{}".utf8)) }
}
enum MAATask { case infrast(InfrastConfiguration) }
