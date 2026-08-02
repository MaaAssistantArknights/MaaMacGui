//
//  MaaApiService.swift
//  MAA
//
//  Hot-update (OTA) downloader for lightweight JSON resources, ported from the
//  Windows MaaApiService + ETagCache. Fetches files from api.maa.plus (falling
//  back to api2.maa.plus), using ETag / Last-Modified conditional requests so
//  unchanged files return 304 and are served from the local cache.
//

import Foundation

actor MaaApiService {
    static let shared = MaaApiService()

    private let primaryBaseURL = "https://api.maa.plus/MaaAssistantArknights/api/"
    private let fallbackBaseURL = "https://api2.maa.plus/MaaAssistantArknights/api/"

    private let session: URLSession

    /// Cache root: documentDirectory/cache (shared with the existing resource cache).
    private let cacheDir = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask).first!
        .appendingPathComponent("cache")

    // ETag / Last-Modified, keyed by full URL, persisted alongside the cache (matching Windows).
    private var etagCache: [String: String] = [:]
    private var lastModifiedCache: [String: String] = [:]
    private var cacheLoaded = false

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public API

    /// Downloads `api` (a path relative to the API base) into `cache/{cacheName}`, using
    /// conditional request headers. `cacheName` defaults to `api` but may differ when the
    /// local layout diverges from the API path (e.g. API `resource/tasks.json` →
    /// cache `resource/tasks/tasks.json`, which is where the core loads it from).
    /// Returns whether the cache was used (304 or network fallback) — `false` means fresh
    /// content was written to disk. Throws only when neither network nor cache can satisfy it.
    @discardableResult
    func requestWithCache(api: String, cacheName: String? = nil) async throws -> Bool {
        loadETagCacheIfNeeded()
        let cacheRelativePath = cacheName ?? api

        // Primary first (no cache fallback so a primary failure proceeds to the fallback host),
        // then fallback host (cache fallback allowed as last resort).
        do {
            return try await tryRequest(
                api: api, cacheRelativePath: cacheRelativePath,
                baseURL: primaryBaseURL, allowCacheFallback: false)
        } catch {
            return try await tryRequest(
                api: api, cacheRelativePath: cacheRelativePath,
                baseURL: fallbackBaseURL, allowCacheFallback: true)
        }
    }

    // MARK: - Request

    private func tryRequest(
        api: String, cacheRelativePath: String, baseURL: String, allowCacheFallback: Bool
    ) async throws -> Bool {
        guard let url = URL(string: baseURL + api) else {
            throw MaaApiError.invalidURL
        }
        let urlKey = url.absoluteString
        let destination = cacheURL(for: cacheRelativePath)
        let cacheExists = FileManager.default.fileExists(atPath: destination.path)

        var request = URLRequest(url: url)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        // Send conditional headers only when a cached copy exists to validate against.
        if cacheExists {
            if let etag = etagCache[urlKey] {
                request.setValue(etag, forHTTPHeaderField: "If-None-Match")
            }
            if let lastModified = lastModifiedCache[urlKey] {
                request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
            }
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            return try fallbackToCache(allowed: allowCacheFallback, cacheExists: cacheExists, underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            return try fallbackToCache(
                allowed: allowCacheFallback, cacheExists: cacheExists, underlying: MaaApiError.badResponse)
        }

        switch http.statusCode {
        case 304:
            // Not modified: existing cache is valid.
            return true
        case 200..<300:
            try writeCache(data: data, to: destination)
            storeValidators(from: http, urlKey: urlKey)
            return false
        default:
            return try fallbackToCache(
                allowed: allowCacheFallback, cacheExists: cacheExists,
                underlying: MaaApiError.httpStatus(http.statusCode))
        }
    }

    private func fallbackToCache(allowed: Bool, cacheExists: Bool, underlying: Error) throws -> Bool {
        if allowed, cacheExists {
            return true
        }
        throw underlying
    }

    private func writeCache(data: Data, to destination: URL) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
    }

    private func storeValidators(from http: HTTPURLResponse, urlKey: String) {
        if let etag = http.value(forHTTPHeaderField: "Etag") {
            etagCache[urlKey] = etag
        }
        if let lastModified = http.value(forHTTPHeaderField: "Last-Modified") {
            lastModifiedCache[urlKey] = lastModified
        }
        saveETagCache()
    }

    // MARK: - Cache Paths

    private func cacheURL(for api: String) -> URL {
        cacheDir.appendingPathComponent(api, isDirectory: false)
    }

    // MARK: - ETag persistence

    private var etagFile: URL { cacheDir.appendingPathComponent("etag.json") }
    private var lastModifiedFile: URL { cacheDir.appendingPathComponent("last_modified.json") }

    private func loadETagCacheIfNeeded() {
        guard !cacheLoaded else { return }
        cacheLoaded = true
        if let data = try? Data(contentsOf: etagFile),
            let dict = try? JSONDecoder().decode([String: String].self, from: data)
        {
            etagCache = dict
        }
        if let data = try? Data(contentsOf: lastModifiedFile),
            let dict = try? JSONDecoder().decode([String: String].self, from: data)
        {
            lastModifiedCache = dict
        }
    }

    private func saveETagCache() {
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        if let data = try? encoder.encode(etagCache) {
            try? data.write(to: etagFile)
        }
        if let data = try? encoder.encode(lastModifiedCache) {
            try? data.write(to: lastModifiedFile)
        }
    }
}

enum MaaApiError: Error {
    case invalidURL
    case badResponse
    case httpStatus(Int)
}
