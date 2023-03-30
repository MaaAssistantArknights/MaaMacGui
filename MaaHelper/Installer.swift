//
//  File.swift
//
//
//  Created by hguandl on 27/3/2023.
//

import AppKit
import injection

public enum Installer {
    static func install(from url: URL) async throws {
        let library = try FileManager.default.url(for: .libraryDirectory,
                                                  in: .userDomainMask,
                                                  appropriateFor: nil,
                                                  create: false)

        let workspace = try FileManager.default.url(for: .itemReplacementDirectory,
                                                    in: .userDomainMask,
                                                    appropriateFor: library,
                                                    create: true)

        defer {
            try? FileManager.default.removeItem(at: workspace)
        }

        try await unzip(from: url, to: workspace)

        let appURL = workspace.appendingPathComponent("Payload").appendingPathComponent("arknights.app")
//        let entitlementsURL = workspace.appendingPathComponent("entitlements").appendingPathExtension("plist")
        let entitlementsURL = URL(fileURLWithPath: "/Users/hguandl/entitlements.plist")
        let mainExecutableURL = appURL.appendingPathComponent("arknights")

//        let entitlements = try await dumpEntitlements(of: appURL)
//        try entitlements.write(toFile: entitlementsURL.path, atomically: true, encoding: .utf8)
//        try entitlements.write(to: entitlementsURL)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for binaryURL in try resolveMachOs(in: appURL) {
                group.addTask {
                    try await thinBinary(for: binaryURL)
                    try await replaceVersion(for: binaryURL)

                    if binaryURL.lastPathComponent != "arknights" {
                        try await sign(for: binaryURL)
                    }
                }
            }
            try await group.waitForAll()
        }

        try await injectTools(into: mainExecutableURL)
        try await sign(for: appURL, with: entitlementsURL)
        try await gateOpen(for: appURL)

//        let outputURL = URL(fileURLWithPath: "/Users/hguandl/Downloads/Arknights/明日方舟.app")
        let outputURL = URL(fileURLWithPath: "/Users/hguandl/Library/Containers/io.playcover.PlayCover/Arknights.app")
        try FileManager.default.moveItem(at: appURL, to: outputURL)

        let config = NSWorkspace.OpenConfiguration()
        config.environment["DYLD_LIBRARY_PATH"] = "/usr/lib/system/introspection"

        try await NSWorkspace.shared.openApplication(at: outputURL, configuration: config)

        print("OKK!")
    }

    private static func unzip(from url: URL, to destination: URL) async throws {
        let task = Task {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-oq", url.path, "-d", destination.path]
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }

        guard try await task.value == 0 else {
            throw InstallerError.unzipFailed
        }
    }

    private static func dumpEntitlements(of url: URL) async throws -> Data {
        let task = Task {
            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            process.arguments = ["-d", "--entitlements", "-", "--xml", url.path]
            process.standardOutput = pipe

            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0,
                  let data = try pipe.fileHandleForReading.readToEnd()
            else {
                throw InstallerError.signFailed
            }

            return data
        }

        return try await task.value
    }

    /// Returns an array of URLs to MachO files within the app
    private static func resolveMachOs(in appURL: URL) throws -> [URL] {
        var resolved = [URL]()

        let resourceKeys = Set<URLResourceKey>([.fileSizeKey, .isRegularFileKey])
        guard let enumerator = FileManager.default.enumerator(
            at: appURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else {
            throw InstallerError.resolveMachOFailed
        }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.isEmpty || fileURL.pathExtension == "dylib" else {
                continue
            }

            guard let resourceValues = try? fileURL.resourceValues(forKeys: resourceKeys),
                  resourceValues.isRegularFile == true,
                  resourceValues.fileSize ?? 0 > 4
            else {
                continue
            }

            let handle = try FileHandle(forReadingFrom: fileURL)
            defer {
                try? handle.close()
            }

            guard let data = try handle.read(upToCount: 4) else {
                continue
            }

            switch data {
            case Data([0xCA, 0xFE, 0xBA, 0xBE]):
                resolved.append(fileURL)
            case Data([0xCF, 0xFA, 0xED, 0xFE]):
                resolved.append(fileURL)
            default:
                continue
            }
        }

        return resolved
    }

    private static func thinBinary(for url: URL, archType: String = "arm64") async throws {
        let task = Task {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/lipo")
            process.arguments = [url.path, "-thin", archType, "-output", url.path]
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }

        guard try await task.value == 0 else {
            throw InstallerError.thinBinaryFailed
        }
    }

    private static func replaceVersion(for url: URL, minos: String = "11.0", sdk: String = "14.0") async throws {
        let task = Task {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/vtool")
            process.arguments = ["-set-build-version", "maccatalyst", minos, sdk,
                                 "-replace", "-output", url.path, url.path]
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }

        guard try await task.value == 0 else {
            throw InstallerError.replaceVersionFailed
        }
    }

    private static func sign(for url: URL, with entitlements: URL? = nil) async throws {
        let task = Task {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")

            if let entitlements {
                process.arguments = ["-s", "-", "-f", url.path,
                                     "--entitlements", entitlements.path,
                                     "--generate-entitlement-der"]
            } else {
                process.arguments = ["-s", "-", "-f", url.path]
            }

            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }

        guard try await task.value == 0 else {
            throw InstallerError.signFailed
        }
    }

    private static func injectTools(into executable: URL) async throws {
        let frameworkDestination = executable.deletingLastPathComponent()
            .appendingPathComponent("Frameworks")
            .appendingPathComponent("PlayTools")
            .appendingPathExtension("framework")

        try FileManager.default.copyItem(at: frameworkURL, to: frameworkDestination)

        try await withCheckedThrowingContinuation { continuation in
            Inject.injectMachO(machoPath: executable.path,
                               cmdType: .loadDylib,
                               backup: false,
                               injectPath: "@rpath/PlayTools.framework/PlayTools")
            { result in
                if result {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: InstallerError.injectHelperFailed)
                }
            }
        }

        let plugInSource = frameworkDestination
            .appendingPathComponent("PlugIns")
        let plugInDestination = executable.deletingLastPathComponent()
            .appendingPathComponent("PlugIns")

        try FileManager.default.moveItem(at: plugInSource, to: plugInDestination)

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await sign(for: frameworkDestination)
            }
            group.addTask {
                try await sign(for: plugInDestination
                    .appendingPathComponent("AKInterface")
                    .appendingPathExtension("bundle"))
            }
            try await group.waitForAll()
        }
    }

    private static func gateOpen(for url: URL) async throws {
        let task = Task {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            process.arguments = ["-d", "-r", "com.apple.quarantine", url.path]
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }

        guard try await task.value == 0 else {
            throw InstallerError.thinBinaryFailed
        }
    }

    private static let frameworkURL = URL(fileURLWithPath: "/Users/hguandl/Library/Frameworks/PlayTools.framework")

    private static let entitlements = """
    <?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>com.apple.security.app-sandbox</key><true/><key>com.apple.security.assets.movies.read-write</key><true/><key>com.apple.security.assets.music.read-write</key><true/><key>com.apple.security.assets.pictures.read-write</key><true/><key>com.apple.security.device.audio-input</key><true/><key>com.apple.security.device.bluetooth</key><true/><key>com.apple.security.device.camera</key><true/><key>com.apple.security.device.microphone</key><true/><key>com.apple.security.device.usb</key><true/><key>com.apple.security.files.downloads.read-write</key><true/><key>com.apple.security.files.user-selected.read-write</key><true/><key>com.apple.security.network.client</key><true/><key>com.apple.security.network.server</key><true/><key>com.apple.security.personal-information.addressbook</key><true/><key>com.apple.security.personal-information.calendars</key><true/><key>com.apple.security.personal-information.location</key><true/><key>com.apple.security.print</key><true/><key>com.apple.security.temporary-exception.sbpl</key><array><string>(allow user-preference-write (preference-domain &quot;.GlobalPreferences&quot;))</string><string>(allow user-preference-read (preference-domain &quot;.GlobalPreferences&quot;))</string><string>(allow file* file-read* file-write* file-write-data file-read-metadata file-ioctl (subpath &quot;/Users/hguandl/Library/Containers/io.playcover.PlayCover&quot;))</string><string>(allow file* file-read* file-read-metadata file-ioctl (subpath &quot;/Users/hguandl/Library/Frameworks/PlayTools.framework&quot;))</string><string>(allow file* file-read* (subpath &quot;/Users/hguandl/Library/Group Containers/&quot;))</string><string>(allow network* ipc-posix*)</string></array></dict></plist>
    """
}
