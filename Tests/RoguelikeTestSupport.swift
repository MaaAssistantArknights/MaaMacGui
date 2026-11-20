import Foundation

protocol MAATaskConfiguration: Codable, Hashable, Sendable {
    associatedtype Params: Encodable
    var params: Params { get }
}
extension MAATaskConfiguration {
    init() { self = try! JSONDecoder().decode(Self.self, from: Data("{}".utf8)) }
}
enum MAATaskType {
    case Roguelike
    var description: String { "Roguelike" }
}
enum MAATask { case roguelike(RoguelikeConfiguration) }

extension String.LocalizationValue {
    static let roguelikePlaytimeLing: Self = "令"
    static let roguelikePlaytimeShu: Self = "黍"
    static let roguelikePlaytimeNian: Self = "年"
}
