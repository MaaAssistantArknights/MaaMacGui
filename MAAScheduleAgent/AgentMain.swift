import AppKit
import Foundation
import MachO

@main struct MAAScheduleAgent {
    @MainActor static func main() async {
        do {
            // Validate the actual executable's containing application before
            // claiming an occurrence. argv[0] is not used as a launch target.
            var count = UInt32(PATH_MAX)
            var path = [CChar](repeating: 0, count: Int(count))
            guard _NSGetExecutablePath(&path, &count) == 0 else { throw BackgroundScheduleError.helperUnavailable }
            let application = try ScheduleAgentLocation.containingApplication(executable: URL(fileURLWithPath: String(cString: path)))
            let directory = try ScheduleSigning.sharedDirectory()
            let checker = BackgroundScheduleCheck(files: BackgroundScheduleFiles(directory: directory),
                                                   ledger: ScheduleOccurrenceStore(directory: directory))
            if let intent = try checker.performIntent(now: .now, calendar: .autoupdatingCurrent) {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                configuration.createsNewApplicationInstance = false
                do {
                    _ = try await NSWorkspace.shared.openApplication(at: application, configuration: configuration)
                } catch {
                    try checker.recordWakeFailure(intent)
                    throw error
                }
            }
        } catch {
            NSLog("Schedule agent check failed: %@", String(describing: error))
            exit(EXIT_FAILURE)
        }
    }
}
