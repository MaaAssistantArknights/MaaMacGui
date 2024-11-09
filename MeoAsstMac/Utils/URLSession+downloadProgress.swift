//
//  URLSession+downloadProgress.swift
//  MAA
//
//  Created by hguandl on 2024/11/9.
//

import Foundation

extension URLSession {
    enum DownloadProgress {
        case progress(Progress)
        case completion(URL)
    }

    func downloadProgress(for request: URLRequest, delegate: (any URLSessionTaskDelegate)? = nil)
        -> AsyncThrowingStream<DownloadProgress, Error>
    {
        AsyncThrowingStream { continuation in
            let task = downloadTask(with: request) { url, response, error in
                if let error {
                    continuation.finish(throwing: error)
                    return
                }

                guard let url, (response as? HTTPURLResponse)?.statusCode == 200 else {
                    continuation.finish(throwing: URLError(.badServerResponse))
                    return
                }

                continuation.yield(.completion(url))
                continuation.finish()
            }

            task.delegate = delegate

            let observation = task.progress.observe(\.fractionCompleted) { progress, _ in
                continuation.yield(.progress(progress))
            }

            continuation.onTermination = { termination in
                observation.invalidate()
                if case .cancelled = termination {
                    task.cancel()
                }
            }

            continuation.yield(.progress(task.progress))
            task.resume()
        }
    }

    func downloadProgress(from url: URL, delegate: (any URLSessionTaskDelegate)? = nil)
        -> AsyncThrowingStream<DownloadProgress, Error>
    {
        downloadProgress(for: URLRequest(url: url), delegate: delegate)
    }
}
