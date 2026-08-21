//
//  FileLogger.swift
//  MAA
//
//  Created by hguandl on 2024/11/28.
//

import Foundation
import System

struct FileLogger: ~Copyable {
    private let fileHandle: FileHandle?

    init(url: URL) throws {
        let fd = try url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                throw CocoaError(.fileReadInvalidFileName)
            }
            return try FileDescriptor.open(
                path, .writeOnly, options: [.create, .append, .closeOnExec],
                permissions: [.ownerReadWrite, .groupRead, .otherRead])
        }
        fileHandle = .init(fileDescriptor: fd.rawValue, closeOnDealloc: true)
    }

    init() {
        fileHandle = nil
    }

    deinit {
        fileHandle?.closeFile()
    }

    func write(_ log: MAALog) {
        let line =
            "[\(log.date.maaFileLogFormat)][\(log.color)]\(log.content.replacingOccurrences(of: "\n", with: " "))\n"
        if let data = line.data(using: .utf8) {
            fileHandle?.write(data)
        }
    }
}
