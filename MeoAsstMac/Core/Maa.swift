//
//  Maa.swift
//  MeoAsstMac
//
//  Created by hguandl on 9/10/2022.
//

import CoreGraphics
import Foundation
import MaaCore
import SwiftyJSON

actor MAAProvider {
    static let shared = MAAProvider()
    private init() {}

    func loadResource(path: String) throws {
        guard AsstLoadResource(path).isTrue else {
            throw MaaCoreError.loadResourceFailed
        }
    }

    func setUserDirectory(path: String) throws {
        guard AsstSetUserDir(path).isTrue else {
            throw MaaCoreError.setUserDirectoryFailed
        }
    }
}

actor MAAHandle {
    private let handle: AsstHandle
    private let uuidPointer = UnsafeMutablePointer<UUID>.allocate(capacity: 1)

    private let callback: AsstApiCallback = { msg, details_json, custom_arg in
        guard let details_json, let custom_arg,
              let detailString = String(cString: details_json, encoding: .utf8)
        else {
            return
        }

        let details = JSON(parseJSON: detailString)
        let message = MaaMessage(code: Int(msg), details: details)
        let uuid = custom_arg.assumingMemoryBound(to: UUID.self).pointee

        NotificationCenter.default.post(name: .MAAReceivedCallbackMessage,
                                        object: message,
                                        userInfo: ["uuid": uuid])
    }

    init(options: MAAInstanceOptions = [:]) throws {
        uuidPointer.initialize(to: UUID())
        handle = AsstCreateEx(callback, uuidPointer)

        for (key, value) in options {
            let success = AsstSetInstanceOption(handle, key.rawValue, value)
            guard success.isTrue else {
                throw MaaCoreError.setInstanceOptionFailed
            }
        }
    }

    deinit {
        AsstDestroy(handle)
        uuidPointer.deallocate()
    }

    nonisolated var uuid: UUID {
        uuidPointer.pointee
    }

    func appendTask(type: MAATask.TypeName, params: String) throws -> Int32 {
        let taskID = AsstAppendTask(handle, type.rawValue, params)
        if taskID == 0 {
            throw MaaCoreError.appendTaskFailed
        } else {
            return taskID
        }
    }

    func connect(adbPath: String, address: String, profile: String) throws {
        _ = AsstAsyncConnect(handle, adbPath, address, profile, 1)
        guard connected else {
            throw MaaCoreError.connectFailed
        }
    }

    func start() throws {
        guard AsstStart(handle).isTrue else {
            throw MaaCoreError.startFailed
        }
    }

    func stop() throws {
        guard AsstStop(handle).isTrue else {
            throw MaaCoreError.stopFailed
        }
    }

    func getImage() throws -> CGImage {
        let size = 1280 * 720 * 3
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)

        if AsstGetImage(handle, buffer, AsstSize(size)) == AsstGetNullSize() {
            throw MaaCoreError.getImageFailed
        }

        let data = Data(bytesNoCopy: buffer, count: size, deallocator: .free)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(pngDataProviderSource: provider, decode: nil,
                                  shouldInterpolate: false, intent: .defaultIntent)
        else {
            throw MaaCoreError.getImageFailed
        }

        return image
    }

    var connected: Bool {
        AsstConnected(handle).isTrue
    }

    var running: Bool {
        AsstRunning(handle).isTrue
    }
}

enum MaaCoreError: Error {
    case loadResourceFailed
    case setUserDirectoryFailed
    case setInstanceOptionFailed
    case appendTaskFailed
    case startFailed
    case stopFailed
    case connectFailed
    case getImageFailed
}

enum MAAInstanceOptionKey: Int32 {
    case Invalid = 0
    case TouchMode = 2
    case DeploymentWithPause = 3
    case AdbLiteEnabled = 4
    case KillAdbOnExit = 5
}

typealias MAAInstanceOptions = [MAAInstanceOptionKey: String]

extension Notification.Name {
    static let MAAReceivedCallbackMessage = Notification.Name("MAAReceivedCallbackMessage")
    static let MAAPreventSystemSleepingChanged = Notification.Name("MAAPreventSystemSleepingChanged")
}

extension JSON {
    func parseTo<T: Decodable>() -> T? {
        guard let data = try? rawData(options: .prettyPrinted) else {
            return nil
        }
        let decoder = JSONDecoder()
        return try? decoder.decode(T.self, from: data)
    }
}

private extension AsstBool {
    var isTrue: Bool { self != 0 }
}
