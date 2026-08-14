//
//  MAAMiniGame.swift
//  MAA
//

import Foundation

/// A mini-game entry supplied by `gui/StageActivityV2.json`.
///
/// The API is intentionally kept independent from the SwiftUI view so that a
/// resource refresh can update the list without rebuilding the view itself.
struct MAAMiniGameEntry: Hashable, Identifiable {
    let display: String
    let displayKey: String?
    let value: String
    let tip: String
    let tipKey: String?
    let minimumRequired: String?
    let utcStartTime: Date?
    let utcExpireTime: Date?

    var id: String { value }

    var localizedDisplay: String {
        Self.localized(key: displayKey, fallback: display)
    }

    var localizedTip: String {
        if let localizedTip = Self.translation(for: tipKey) {
            return localizedTip
        }
        if !tip.isEmpty {
            return tip
        }
        if let displayKey, let localizedTip = Self.translation(for: displayKey + "Tip") {
            return localizedTip
        }
        return display
    }

    func isOpen(at date: Date = Date()) -> Bool {
        if let utcStartTime, date <= utcStartTime {
            return false
        }
        return !isExpired(at: date)
    }

    /// Returns true only when the activity has an explicit expiry timestamp
    /// and that timestamp has passed. Missing metadata is deliberately not
    /// treated as expired, so an old built-in Mac entry is not removed merely
    /// because a newer activity file omitted it.
    func isExpired(at date: Date = Date()) -> Bool {
        guard let utcExpireTime else { return false }
        return date >= utcExpireTime
    }

    private static func localized(key: String?, fallback: String) -> String {
        translation(for: key) ?? (fallback.isEmpty ? key ?? "" : fallback)
    }

    private static func translation(for key: String?) -> String? {
        guard let key, !key.isEmpty else { return nil }

        let value = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
        // `localizedString` returns the key itself when the key is not present
        // in the current locale.
        return value == key ? nil : value
    }
}

/// Loads the mini-game list from the same activity resource used by the
/// Windows GUI. The loader is deliberately tolerant because old resource
/// packages may still contain `StageActivity.json`, while a fresh install may
/// not have either file until the first OTA refresh completes.
enum MAAMiniGameCatalog {
    private static let stageFileNames = ["StageActivityV2.json", "StageActivity.json"]

    // Activity timestamps use a local wall-clock value together with a
    // separate hour offset. Keep the parser fixed to GMT so it can be shared
    // without mutating a formatter's time zone on every entry.
    private static let activityDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return formatter
    }()

    private static let iso8601DateFormatter = ISO8601DateFormatter()

    private static let iso8601FractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private struct ParsedCatalog {
        let openEntries: [MAAMiniGameEntry]
        let expiredValues: Set<String>
    }

    static var fallbackEntries: [MAAMiniGameEntry] {
        var seenValues = Set<String>()
        return MiniGameOption.allCases.compactMap { option in
            guard seenValues.insert(option.taskName).inserted else { return nil }
            return option.catalogEntry
        }
    }

    static func load(client: MAAClientChannel, now: Date = Date()) -> [MAAMiniGameEntry] {
        for url in resourceURLs {
            guard let data = try? Data(contentsOf: url) else { continue }
            guard let catalog = parseCatalog(data: data, clientKeys: clientKeys(for: client), now: now) else {
                continue
            }
            return merge(dynamicEntries: catalog.openEntries, hiddenValues: catalog.expiredValues)
        }

        return fallbackEntries
    }

    /// Parses a StageActivity document. A `nil` result means that the document
    /// is not a recognized activity document and should not replace the local
    /// fallback list. An empty array is valid and means that the selected
    /// client currently has no dynamic mini-games.
    static func parse(
        data: Data,
        clientKeys: [String],
        now: Date = Date()
    ) -> [MAAMiniGameEntry]? {
        parseCatalog(data: data, clientKeys: clientKeys, now: now)?.openEntries
    }

    private static func parseCatalog(
        data: Data,
        clientKeys: [String],
        now: Date
    ) -> ParsedCatalog? {
        guard let root = try? JSONSerialization.jsonObject(with: data),
            let rootObject = root as? [String: Any]
        else {
            return nil
        }

        guard let clientObject = clientObject(in: rootObject, clientKeys: clientKeys) else {
            return nil
        }

        guard let miniGameToken = value(in: clientObject, key: "miniGame") else {
            return nil
        }

        let tokens: [Any]
        if let array = miniGameToken as? [Any] {
            tokens = array
        } else {
            tokens = [miniGameToken]
        }

        var entries = [MAAMiniGameEntry]()
        var seenValues = Set<String>()
        for token in tokens {
            guard let entry = parseEntry(token), seenValues.insert(entry.value).inserted else {
                continue
            }
            entries.append(entry)
        }

        let openEntries = entries.filter { $0.isOpen(at: now) }
        let expiredValues = Set(
            entries
                .filter { $0.isExpired(at: now) }
                .map(\.value)
        )
        return ParsedCatalog(openEntries: openEntries, expiredValues: expiredValues)
    }

    private static var resourceURLs: [URL] {
        var roots = [URL]()
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first

        if let documents {
            roots.append(documents.appendingPathComponent("cache", isDirectory: true))
            roots.append(documents.appendingPathComponent("resource", isDirectory: true))
        }

        if let bundleResource = Bundle.main.resourceURL {
            roots.append(bundleResource.appendingPathComponent("resource", isDirectory: true))
            roots.append(bundleResource)
        }

        // Prefer every V2 candidate over every legacy V1 candidate. This
        // avoids a stale cached V1 file masking a newer bundled V2 file.
        var candidates = [URL]()
        for fileName in stageFileNames {
            for root in roots {
                candidates.append(
                    root.appendingPathComponent("gui", isDirectory: true)
                        .appendingPathComponent(fileName, isDirectory: false)
                )
                candidates.append(root.appendingPathComponent(fileName, isDirectory: false))
            }
        }

        // Keep the list free of duplicates when a build happens to place the
        // resource directory at the bundle root as well as under `resource`.
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.path).inserted }
    }

    private static func clientKeys(for client: MAAClientChannel) -> [String] {
        switch client {
        case .Bilibili:
            // The resource API uses the Official section for Bilibili as well.
            return [MAAClientChannel.Official.rawValue]
        default:
            return [client.rawValue, MAAClientChannel.Official.rawValue]
        }
    }

    private static func clientObject(in root: [String: Any], clientKeys: [String]) -> [String: Any]? {
        for key in clientKeys {
            if let object = object(in: root, key: key) {
                return object
            }
        }

        // Accept a document that is already the client section. This is useful
        // for small local fixtures and costs nothing for normal API responses.
        if value(in: root, key: "miniGame") != nil {
            return root
        }
        return nil
    }

    private static func parseEntry(_ token: Any) -> MAAMiniGameEntry? {
        if let value = token as? String, !value.isEmpty {
            return MAAMiniGameEntry(
                display: value,
                displayKey: nil,
                value: value,
                tip: "",
                tipKey: nil,
                minimumRequired: nil,
                utcStartTime: nil,
                utcExpireTime: nil
            )
        }

        guard let object = token as? [String: Any] else { return nil }

        let display = string(in: object, key: "Display") ?? ""
        let displayKey = string(in: object, key: "DisplayKey")
        let rawValue = string(in: object, key: "Value") ?? string(in: object, key: "value")
        let value: String
        if let rawValue, !rawValue.isEmpty {
            value = rawValue
        } else if !display.isEmpty {
            value = display
        } else {
            value = displayKey ?? ""
        }
        guard !value.isEmpty else { return nil }

        let tip = string(in: object, key: "Tip") ?? ""
        let tipKey = string(in: object, key: "TipKey")
        let minimumRequired = string(in: object, key: "MinimumRequired")
        let timeZone = integer(in: object, key: "TimeZone") ?? 0

        let parsedStart = date(in: object, key: "UtcStartTime", timeZone: timeZone)
        let parsedExpire = date(in: object, key: "UtcExpireTime", timeZone: timeZone)
        return MAAMiniGameEntry(
            display: display.isEmpty ? value : display,
            displayKey: displayKey,
            value: value,
            tip: tip,
            tipKey: tipKey,
            minimumRequired: minimumRequired,
            utcStartTime: parsedStart,
            utcExpireTime: parsedExpire
        )
    }

    private static func merge(
        dynamicEntries: [MAAMiniGameEntry],
        hiddenValues: Set<String>
    ) -> [MAAMiniGameEntry] {
        // Dynamic entries are inserted first so that a resource-provided
        // display/tip replaces the built-in copy for the same task. A built-in
        // entry is hidden only when the activity resource explicitly marks the
        // same task as expired; omitted/undated entries stay available.
        let builtInEntries = fallbackEntries
        var result = dynamicEntries
        var seenValues = Set(dynamicEntries.map(\.value))
        for entry in builtInEntries
            where !hiddenValues.contains(entry.value) && seenValues.insert(entry.value).inserted
        {
            result.append(entry)
        }
        return result
    }

    private static func object(in object: [String: Any], key: String) -> [String: Any]? {
        value(in: object, key: key) as? [String: Any]
    }

    private static func value(in object: [String: Any], key: String) -> Any? {
        if let value = object[key] { return value }
        return object.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }

    private static func string(in object: [String: Any], key: String) -> String? {
        let value = value(in: object, key: key)
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func integer(in object: [String: Any], key: String) -> Int? {
        let value = value(in: object, key: key)
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func date(in object: [String: Any], key: String, timeZone: Int) -> Date? {
        guard let string = string(in: object, key: key), !string.isEmpty else { return nil }

        if let date = activityDateFormatter.date(from: string) {
            // The activity file stores the wall-clock value in `timeZone`,
            // while Date represents an absolute UTC instant.
            return date.addingTimeInterval(-TimeInterval(timeZone) * 60 * 60)
        }

        // Be liberal with hand-written/local fixture files.
        return iso8601DateFormatter.date(from: string)
            ?? iso8601FractionalDateFormatter.date(from: string)
    }
}
