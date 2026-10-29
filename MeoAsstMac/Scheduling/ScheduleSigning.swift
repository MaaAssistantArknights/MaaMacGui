import Foundation
import Security

/// macOS App Group identifiers are derived from the actual signing team. An
/// ad-hoc binary has no team and must never fall back to a raw Library path.
enum ScheduleSigning {
    static let groupSuffix = "com.hguandl.MeoAsstMac.Schedule"

    static func sharedDirectory() throws -> URL {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { throw BackgroundScheduleError.signingRequired }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { throw BackgroundScheduleError.signingRequired }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let values = information as? [String: Any],
              let team = values[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty,
              let entitlements = values[kSecCodeInfoEntitlementsDict as String] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String],
              groups.contains(team + "." + groupSuffix),
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: team + "." + groupSuffix)
        else { throw BackgroundScheduleError.signingRequired }
        return container.appendingPathComponent("Schedule", isDirectory: true)
    }
}
