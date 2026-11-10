import Foundation

enum ScheduleAgentLocation {
    static func containingApplication(executable: URL) throws -> URL {
        let executable = executable.resolvingSymlinksInPath()
        guard executable.lastPathComponent == "MAAScheduleAgent",
              executable.deletingLastPathComponent().lastPathComponent == "MacOS",
              executable.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "Contents"
        else { throw BackgroundScheduleError.helperUnavailable }
        let application = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard application.pathExtension == "app", let bundle = Bundle(url: application),
              bundle.bundleIdentifier == "com.hguandl.MeoAsstMac"
        else { throw BackgroundScheduleError.helperUnavailable }
        return application
    }
}
