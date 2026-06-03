//
//  StageCodeResolver.swift
//  MAA
//
//  Resolves a copilot's internal stage id (e.g. "act50side_01") to the in-game stage
//  code shown on screen (e.g. "TD-1"), which is what the core needs for auto-navigation
//  in a copilot list. Mirrors the Windows `DataHelper.FindMap().Code` lookup with a
//  title-based fallback (`FindStageName`).
//

import Foundation

enum StageCodeResolver {
    /// Resolves the navigation code for a copilot.
    /// - Parameters:
    ///   - stageName: the copilot's `stage_name` (internal stage id, e.g. "act50side_01").
    ///   - title: the copilot documentation title (e.g. "TD-1 - 硬壳下的胆小鬼"), used as fallback.
    /// - Returns: the stage code used for navigation (e.g. "TD-1"); falls back to `stageName`.
    static func navigationCode(stageName: String, title: String?) -> String {
        if let code = codeFromTilePos(stageId: stageName), !code.isEmpty {
            return code
        }
        if let code = stageCodeFromTitle(title), !code.isEmpty {
            return code
        }
        // Last resort: the internal stage name. For permanent stages whose stage_name already
        // equals the code (rare), this still works.
        return stageName
    }

    // MARK: - Tile-Pos lookup (authoritative)

    /// Looks up the `code` field from the Arknights-Tile-Pos resource for the given stage id.
    /// Tile-Pos files are named `{stageId}-...-level_{stageId}.json`.
    private static func codeFromTilePos(stageId: String) -> String? {
        guard !stageId.isEmpty else { return nil }

        for directory in tilePosDirectories() {
            guard let url = matchingTilePosFile(in: directory, stageId: stageId) else { continue }
            guard let data = try? Data(contentsOf: url),
                let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let code = obj["code"] as? String
            else {
                continue
            }
            return code
        }
        return nil
    }

    /// Finds the Tile-Pos file whose name starts with `{stageId}-` (the leading token is the
    /// stage id). Returns the first match.
    private static func matchingTilePosFile(in directory: URL, stageId: String) -> URL? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return nil
        }
        let prefix = stageId + "-"
        return entries.first { $0.lastPathComponent.hasPrefix(prefix) }
    }

    /// Candidate Tile-Pos directories: user-updated resource first, then the bundled resource.
    private static func tilePosDirectories() -> [URL] {
        var dirs: [URL] = []
        let documents = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first
        if let userResource = documents?
            .appendingPathComponent("resource")
            .appendingPathComponent("Arknights-Tile-Pos")
        {
            dirs.append(userResource)
        }
        if let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("resource")
            .appendingPathComponent("Arknights-Tile-Pos")
        {
            dirs.append(bundled)
        }
        return dirs.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: - Title fallback

    /// Extracts a stage code from a copilot title, mirroring the Windows `FindStageName` regex.
    /// e.g. "TD-1 - 硬壳下的胆小鬼" → "TD-1".
    private static func stageCodeFromTitle(_ title: String?) -> String? {
        guard let title, !title.isEmpty else { return nil }
        let pattern = #"(?:[a-zA-Z]{0,3})(?:\d{0,2})-(?:(?:A|B|C|D|EX|S|TR|MO)-?)?(?:\d{1,2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(title.startIndex..., in: title)
        guard let match = regex.firstMatch(in: title, range: range),
            let matchRange = Range(match.range, in: title)
        else {
            return nil
        }
        return String(title[matchRange])
    }
}
