//
//  FileLogger.swift
//  MAA
//
//  Created by hguandl on 2024/11/28.
//

import Foundation

struct FileLogger: ~Copyable {
    private let fileHandle: FileHandle?

    init(url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        fileHandle = try FileHandle(forWritingTo: url)
    }

    init() {
        fileHandle = nil
    }

    deinit {
        fileHandle?.closeFile()
    }

    func write(_ log: MAALog) {
        let line = "[\(log.date?.description ?? "")][\(log.color)]\(log.content)\n"
        if let data = line.data(using: .utf8) {
            fileHandle?.write(data)
        }
    }
}
