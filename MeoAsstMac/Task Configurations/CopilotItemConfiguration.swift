import Foundation

struct CopilotItemConfiguration: Codable {
    var enabled: Bool = true
    var filename: String
    var name: String
    var is_raid: Bool
    var need_navigate: Bool
    var navigate_name: String

    enum CodingKeys: String, CodingKey {
        case enabled
        case filename
        case name
        case is_raid
        case need_navigate
        case navigate_name
    }
}
