//
//  URL+contentType.swift
//  MAA
//
//  Created by hguandl on 2026/8/12.
//

import Foundation
import UniformTypeIdentifiers

extension URL {
    var contentType: UTType? {
        let values = try? resourceValues(forKeys: [.contentTypeKey])
        return values?.contentType
    }

    var isDirectory: Bool {
        contentType?.conforms(to: .directory) ?? false
    }
}
