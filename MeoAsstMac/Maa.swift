//
//  Maa.swift
//  MeoAsstMac
//
//  Created by hguandl on 9/10/2022.
//

import Foundation
import MaaCore

@globalActor
public struct MaaActor {
    public actor MaaActor {}

    public static let shared = MaaActor()
}

@MaaActor
public struct Maa {
    static var resourceLoaded = false

    private let handle: AsstHandle

    public static func loadResource(path: String) -> Bool {
        if AsstLoadResource(path) != 0 {
            resourceLoaded = true
            return true
        }
        return false
    }

    public static func setUserDirectory(path: String) -> Bool {
        AsstSetUserDir(path) != 0
    }

    public init(options: [MaaInstanceOptionKey: String]? = nil) {
        let callback: AsstApiCallback = { msg, details, _ in
            if msg >= 20000 {
                return
            }
            if let details = details {
                let details = String(cString: details, encoding: .utf8) ?? "<nil>"
                let message = MaaMessage(msg: msg, details: details)
                Self.publishLogMessage(message: message)
            }
        }

        self.handle = AsstCreateEx(callback, nil)

        options?.forEach { key, value in
            AsstSetInstanceOption(handle, key.rawValue, value)
        }
    }

    public func appendTask(taskType: String, taskConfig: String) -> Int32 {
        AsstAppendTask(handle, taskType, taskConfig)
    }

    public func connect(adbPath: String, address: String, profile: String) -> Bool {
        AsstConnect(handle, adbPath, address, profile) != 0
    }

    public func start() -> Bool {
        AsstStart(handle) != 0
    }

    public func stop() -> Bool {
        AsstStop(handle) != 0
    }

    public func destroy() {
        AsstDestroy(handle)
    }

    public var running: Bool {
        AsstRunning(handle) != 0
    }

    public static var version: String? {
        if let versionString = AsstGetVersion() {
            return String(cString: versionString)
        }
        return nil
    }

    static func publishLogMessage(message: MaaMessage) {
        NotificationCenter.default.post(name: .MAAReceivedCallbackMessage, object: message)
    }
}

public extension Notification.Name {
    static let MAAReceivedCallbackMessage = Notification.Name("MAAReceivedCallbackMessage")
}

public enum MaaInstanceOptionKey: Int32 {
    case Invalid = 0
    case TouchMode = 2
}
