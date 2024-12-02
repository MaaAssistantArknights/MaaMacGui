//
//  FileLogger.swift
//  MAA
//
//  Created by hguandl on 2024/11/28.
//

import Foundation

struct FileLogger: ~Copyable {
    private let fileHandle: FileHandle

    init(url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        fileHandle = try FileHandle(forWritingTo: url)
    }

    deinit {
        fileHandle.closeFile()
    }

    func write(_ log: MAALog) {
        let line = "[\(log.date?.description ?? "")][\(log.color)]\(log.content)\n"
        if let data = line.data(using: .utf8) {
            fileHandle.write(data)
        }
    }
}

@available(swift, introduced: 5.9, deprecated: 6.0, message: "Use `Optional<FileLogger>` directly.")
enum OptionalFileLogger: ~Copyable {
    case some(FileLogger)
    case none

    init(url: URL) throws {
        self = try .some(FileLogger(url: url))
    }

    func write(_ log: MAALog) {
        switch self {
        case .some(let fileLogger):
            fileLogger.write(log)
        case .none:
            break
        }
    }
}
