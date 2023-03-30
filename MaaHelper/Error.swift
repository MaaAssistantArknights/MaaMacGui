//
//  File.swift
//
//
//  Created by hguandl on 27/3/2023.
//

import Foundation

public enum InstallerError: Error {
    case unzipFailed
    case resolveMachOFailed
    case thinBinaryFailed
    case replaceVersionFailed
    case signFailed
    case injectHelperFailed
}
