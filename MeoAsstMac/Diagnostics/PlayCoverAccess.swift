import AppKit
import Darwin
import Foundation
import UniformTypeIdentifiers

@MainActor final class PlayCoverAccess: ObservableObject {
    enum Location: String {
        case application, data
        var key: String { "PlayCoverDiagnostics.Bookmark.\(rawValue)" }
    }
    @Published private(set) var applicationURL: URL
    @Published private(set) var dataURL: URL
    @Published private(set) var message: String?
    private var scopedURLs = [Location: URL]()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        applicationURL = Self.defaultApplicationURL
        dataURL = Self.defaultDataURL
        restore(.application)
        restore(.data)
    }

    /// Explicit locations for isolated checks; never restores real user grants.
    init(applicationURL: URL, dataURL: URL, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.applicationURL = applicationURL
        self.dataURL = dataURL
    }

    deinit {
        for url in scopedURLs.values { url.stopAccessingSecurityScopedResource() }
    }

    static var userHome: URL {
        // Foundation redirects even homeDirectory(forUser: NSUserName()) to the
        // app's container in a sandbox. Resolve the account home using POSIX;
        // this locates a path, it does not grant permission to read it.
        let suggestedSize = sysconf(_SC_GETPW_R_SIZE_MAX)
        var size = suggestedSize > 0 ? min(Int(suggestedSize), 1_048_576) : 16_384
        while size <= 1_048_576 {
            var record = passwd()
            var result: UnsafeMutablePointer<passwd>?
            var buffer = [CChar](repeating: 0, count: size)
            let (status, path) = buffer.withUnsafeMutableBufferPointer { pointer -> (Int32, String?) in
                let status = getpwuid_r(getuid(), &record, pointer.baseAddress, pointer.count, &result)
                // pw_dir points into this buffer, so copy it before the pointer
                // leaves the closure that guarantees the buffer's lifetime.
                let path = status == 0 && result != nil ? record.pw_dir.map { String(cString: $0) } : nil
                return (status, path)
            }
            if status == ERANGE {
                size *= 2
                continue
            }
            if let path {
                if path.hasPrefix("/"), path != "/" { return URL(fileURLWithPath: path, isDirectory: true) }
            }
            break
        }
        return URL(fileURLWithPath: "/Users/\(NSUserName())", isDirectory: true)
    }

    static var defaultApplicationURL: URL { URL(fileURLWithPath: "/Applications/PlayCover.app") }
    static var defaultDataURL: URL { userHome.appendingPathComponent("Library/Containers/io.playcover.PlayCover") }

    /// Default paths use narrowly scoped read-only entitlements. macOS presents
    /// its own cross-app data consent when a scan first reads the container.
    /// Only nonstandard paths need an Open panel and a persisted bookmark.
    func useDefaultLocations() {
        for location in [Location.application, .data] {
            scopedURLs.removeValue(forKey: location)?.stopAccessingSecurityScopedResource()
            defaults.removeObject(forKey: location.key)
        }
        applicationURL = Self.defaultApplicationURL
        dataURL = Self.defaultDataURL
        message = nil
    }

    func choose(_ location: Location) async {
        let panel = NSOpenPanel()
        panel.canChooseFiles = location == .application
        panel.canChooseDirectories = location == .data
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.prompt = String(localized: "授权读取")
        if location == .application {
            panel.title = String(localized: "选择 PlayCover 应用")
            panel.message = String(localized: "选择 /Applications 中的 PlayCover.app，用于读取版本与发行信息。")
            panel.allowedContentTypes = [.applicationBundle]
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
        } else {
            panel.title = String(localized: "选择 PlayCover 数据目录")
            panel.message = String(localized: "选择 ~/Library/Containers/io.playcover.PlayCover，游戏与 App Settings 保存在这里。")
            panel.directoryURL = Self.defaultDataURL
        }
        guard await panel.begin() == .OK, let url = panel.url else {
            message = String(localized: "授权已取消，仍可检查已获得的信息。")
            return
        }
        do {
            if location == .application {
                let info = try PlayCoverStaticChecks.plist(at: url.appendingPathComponent("Contents/Info.plist"))
                guard info["CFBundleIdentifier"] as? String == "io.playcover.PlayCover" else {
                    throw CocoaError(.fileReadUnsupportedScheme)
                }
            } else {
                guard url.lastPathComponent == "io.playcover.PlayCover" else {
                    throw CocoaError(.fileReadUnsupportedScheme)
                }
            }
            let bookmark = try url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil, relativeTo: nil)
            try adopt(url, for: location)
            defaults.set(bookmark, forKey: location.key)
            message = nil
        } catch { message = error.localizedDescription }
    }

    private func restore(_ location: Location) {
        guard let bookmark = defaults.data(forKey: location.key) else { return }
        do {
            var stale = false
            let url = try URL(
                resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                relativeTo: nil, bookmarkDataIsStale: &stale)
            guard !stale, url.startAccessingSecurityScopedResource() else {
                message = String(localized: "自定义目录授权已失效，将检测默认路径；需要时重新选择自定义位置。")
                return
            }
            scopedURLs[location] = url
            if location == .application { applicationURL = url } else { dataURL = url }
        } catch { message = String(localized: "自定义目录授权恢复失败，将检测默认路径：\(error.localizedDescription)") }
    }

    private func adopt(_ url: URL, for location: Location) throws {
        guard url.startAccessingSecurityScopedResource() else { throw CocoaError(.fileReadNoPermission) }
        scopedURLs.removeValue(forKey: location)?.stopAccessingSecurityScopedResource()
        scopedURLs[location] = url
        if location == .application { applicationURL = url } else { dataURL = url }
    }
}
