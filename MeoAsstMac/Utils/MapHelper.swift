//
//  MapHelper.swift
//  MAA
//
//  Created by ninekirin on 2025/5/8.
//

import Foundation

struct MapInfo: Codable {
    var code: String?
    var filename: String?
    var levelId: String?
    var name: String?
    var stageId: String?
    var height: Int
    var width: Int

    private enum CodingKeys: String, CodingKey {
        case code = "code"
        case filename = "filename"
        case levelId = "levelId"
        case name = "name"
        case stageId = "stageId"
        case height = "height"
        case width = "width"
    }
}

class MapHelper {
    static private(set) var mapData: [MapInfo] = []

    static func loadMapData() {
        let path = Bundle.main.resourceURL!
            .appendingPathComponent("resource")
            .appendingPathComponent("Arknights-Tile-Pos")
            .appendingPathComponent("overview.json")

        guard let data = try? Data(contentsOf: path),
            let jsonObj = try? JSONDecoder().decode([String: MapInfo].self, from: data)
        else {
            return
        }

        mapData = Array(jsonObj.values)
    }

    static func findMap(_ mapId: String) -> MapInfo? {
        return mapData.first { map in
            [map.code, map.name, map.stageId, map.levelId].contains { $0 == mapId }
        }
    }
}
