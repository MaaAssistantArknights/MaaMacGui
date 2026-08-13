//
//  FileManager+Atomic.swift
//  MAA
//
//  Created by hguandl on 2026/8/14.
//

import Foundation

extension FileManager {
    func safelyOverwriteItemAt(
        _ originalItemURL: URL, withItemAt newItemURL: URL,
        backupItemName: String? = nil, options: FileManager.ItemReplacementOptions = []
    ) throws -> URL? {
        let tmpDirectory = try url(
            for: .itemReplacementDirectory, in: .userDomainMask,
            appropriateFor: originalItemURL, create: true
        )
        defer {
            try? removeItem(at: tmpDirectory)
        }
        let tmpURL = tmpDirectory.appending(path: newItemURL.lastPathComponent)
        try copyItem(at: newItemURL, to: tmpURL)
        return try replaceItemAt(
            originalItemURL, withItemAt: tmpURL,
            backupItemName: backupItemName, options: options)
    }

    func copyItemOverwriting(at srcURL: URL, to dstURL: URL) throws {
        do {
            try copyItem(at: srcURL, to: dstURL)
        } catch let error as CocoaError where error.code == .fileWriteFileExists {
            _ = try safelyOverwriteItemAt(dstURL, withItemAt: srcURL, options: .usingNewMetadataOnly)
        }
    }

    func moveItemOverwriting(at srcURL: URL, to dstURL: URL) throws {
        do {
            try moveItem(at: srcURL, to: dstURL)
        } catch let error as CocoaError where error.code == .fileWriteFileExists {
            _ = try safelyOverwriteItemAt(dstURL, withItemAt: srcURL, options: .usingNewMetadataOnly)
            try removeItem(at: srcURL)
        }
    }
}
