//
//  MAAHelperProtocol.swift
//  MAAHelper
//
//  Created by hguandl on 26/4/2023.
//

import Foundation

@objc protocol MAAHelperProtocol {
    func startGame(bundleName: String, with reply: @escaping (Bool) -> Void)
}
