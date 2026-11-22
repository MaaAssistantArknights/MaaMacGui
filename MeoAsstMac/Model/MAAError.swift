//
//  MAAError.swift
//  MAA
//
//  Created by hguandl on 30/4/2023.
//

import Foundation

enum MAAError: Error {
    case emptyItemObject
    case gameStartFailed
    /// Core 仍在运行，暂时不能重新连接实例。
    case handleAlreadyRunning
    case imageUnavailable
}
