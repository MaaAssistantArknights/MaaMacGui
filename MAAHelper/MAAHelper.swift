//
//  MAAHelper.swift
//  MAAHelper
//
//  Created by hguandl on 26/4/2023.
//

import AppKit

class MAAHelper: NSObject, MAAHelperProtocol {
    @objc func startGame(bundleName: String, with reply: @escaping (Bool) -> Void) {
        guard let appBundle = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Containers")
            .appendingPathComponent("io.playcover.PlayCover")
            .appendingPathComponent(bundleName)
        else {
            reply(false)
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.environment["DYLD_LIBRARY_PATH"] = "/usr/lib/system/introspection"

        NSWorkspace.shared.open(appBundle, configuration: config) { _, error in
            if error != nil {
                reply(false)
            } else {
                reply(true)
            }
        }
    }
}
