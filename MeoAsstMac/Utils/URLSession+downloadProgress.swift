//
//  URLSession+downloadProgress.swift
//  MAA
//
//  Created by hguandl on 2024/11/9.
//

import Foundation

extension URLSession {
    /// Retrieves the contents of a URL based on the specified URL request and tracks the progress of saving file to the destination URL.
    /// - Returns: An [AsyncThrowingStream](/documentation/swift/asyncthrowingstream) of [Progress](/documentation/foundation/progress).
    func downloadTo(_ destination: URL, for request: URLRequest, delegate: (any URLSessionTaskDelegate)? = nil)
        -> AsyncThrowingStream<Progress, Error>
    {
        AsyncThrowingStream { continuation in
            let task = downloadTask(with: request) { url, response, error in
                defer {
                    if let url {
                        try? FileManager.default.removeItem(at: url)
                    }
                }

                if let error {
                    continuation.finish(throwing: error)
                    return
                }

                guard let url, (response as? HTTPURLResponse)?.statusCode == 200 else {
                    continuation.finish(throwing: URLError(.badServerResponse))
                    return
                }

                do {
                    try FileManager.default.moveItem(at: url, to: destination)
                } catch {
                    continuation.finish(throwing: error)
                    return
                }

                continuation.finish()
            }

            task.delegate = delegate

            let observation = task.progress.observe(\.fractionCompleted) { progress, _ in
                continuation.yield(progress)
            }

            continuation.onTermination = { termination in
                observation.invalidate()
                if case .cancelled = termination {
                    task.cancel()
                }
            }

            continuation.yield(task.progress)
            task.resume()
        }
    }

    /// Retrieves the contents of a URL and tracks the progress of saving file to the destination URL.
    /// - Returns: An [AsyncThrowingStream](/documentation/swift/asyncthrowingstream) of [Progress](/documentation/foundation/progress).
    func downloadTo(_ destination: URL, from url: URL, delegate: (any URLSessionTaskDelegate)? = nil)
        -> AsyncThrowingStream<Progress, Error>
    {
        downloadTo(destination, for: URLRequest(url: url), delegate: delegate)
    }
}
