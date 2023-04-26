//
//  main.swift
//  MAAHelper
//
//  Created by hguandl on 26/4/2023.
//

import Foundation

class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: MAAHelperProtocol.self)

        let exportedObject = MAAHelper()
        newConnection.exportedObject = exportedObject

        newConnection.resume()
        return true
    }
}

let delegate = ServiceDelegate()

let listener = NSXPCListener.service()
listener.delegate = delegate

listener.resume()
