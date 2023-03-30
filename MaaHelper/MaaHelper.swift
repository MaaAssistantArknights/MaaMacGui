//
//  MaaHelper.swift
//  MaaHelper
//
//  Created by hguandl on 29/3/2023.
//

import Foundation
import OSLog

/// This object implements the protocol which we have defined. It provides the actual behavior for the service. It is 'exported' by the service to make it available to the process hosting the service over an NSXPCConnection.
class MaaHelper: NSObject, MaaHelperProtocol {
    
    /// This implements the example protocol. Replace the body of this class with the implementation of this service's protocol.
    @objc func uppercase(string: String, with reply: @escaping (String) -> Void) {
        let response = string.uppercased()
        reply(response)
    }
    
    @objc func installApp(url: URL, with reply: @escaping (Bool) -> Void) {
        os_log("HERE")
        Task {
            do {
                try await Installer.install(from: url)
                reply(true)
            } catch {
                os_log("Error: \(error)")
                reply(false)
            }
        }
    }
}
