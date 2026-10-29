import Foundation
import Combine

struct HookCommand: Codable, Equatable {
    var bookmark: Data
    var displayPath: String
    var arguments: [String] = []
    var shellScript = true

    func resolve() throws -> URL {
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], bookmarkDataIsStale: &stale)
        guard !stale else { throw HookError.permissionRequired }
        return url
    }
}

struct HookConfiguration: Codable, Equatable {
    var enabled = false
    var before: HookCommand?
    var after: HookCommand?
    var timeoutSeconds = 60
}

enum HookError: LocalizedError {
    case permissionRequired, invalidExecutable, launch(Int32)
    var errorDescription: String? {
        switch self {
        case .permissionRequired: return String(localized: "重新选择脚本以授予访问权限")
        case .invalidExecutable: return String(localized: "所选程序不可执行或脚本无法读取")
        case .launch(let code): return String(localized: "无法启动脚本") + " (\(code))"
        }
    }
}

@MainActor
final class HookSettingsStore: ObservableObject {
    @Published var configuration: HookConfiguration {
        didSet {
            if let data = try? JSONEncoder().encode(configuration) { defaults.set(data, forKey: "MAADailyRunHooks") }
        }
    }
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        configuration = defaults.data(forKey: "MAADailyRunHooks")
            .flatMap { try? JSONDecoder().decode(HookConfiguration.self, from: $0) } ?? HookConfiguration()
    }
}
