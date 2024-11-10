//
//  FileManager+unzipProgress.swift
//  MAA
//
//  Created by hguandl on 2024/11/9.
//

import Foundation
import ZIPFoundation

extension FileManager {
    /// Unzips the contents at the specified source URL and tracks the progress to the destination URL.
    /// - Returns: An [AsyncThrowingStream](/documentation/swift/asyncthrowingstream) of [Progress](/documentation/foundation/progress).
    func unzipItemAt(
        _ sourceURL: URL, to destinationURL: URL,
        skipCRC32: Bool = false, allowUncontainedSymlinks: Bool = false,
        pathEncoding: String.Encoding? = nil
    ) -> AsyncThrowingStream<Progress, Error> {
        AsyncThrowingStream { continuation in
            let progress = Progress()

            let observation = progress.observe(\.fractionCompleted) { progress, _ in
                continuation.yield(progress)
            }

            continuation.onTermination = { termination in
                observation.invalidate()
                if case .cancelled = termination {
                    progress.cancel()
                }
            }

            Task.detached {
                do {
                    continuation.yield(progress)
                    try self.unzipItem(
                        at: sourceURL, to: destinationURL,
                        skipCRC32: skipCRC32, allowUncontainedSymlinks: allowUncontainedSymlinks,
                        progress: progress, pathEncoding: pathEncoding
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
