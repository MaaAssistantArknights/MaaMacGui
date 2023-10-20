//
//  MAAHelperProtocol.swift
//  MAAHelper
//
//  Created by hguandl on 26/4/2023.
//

import Foundation
import AppKit

@objc protocol MAAHelperProtocol {
    func startGame(bundleName: String, with reply: @escaping (Bool) -> Void)
    func terminateGame(processIdentifier: Int32)
}
