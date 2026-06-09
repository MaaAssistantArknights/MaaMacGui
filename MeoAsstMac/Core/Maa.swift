//
//  Maa.swift
//  MeoAsstMac
//
//  Created by hguandl on 9/10/2022.
//

import CoreGraphics
import Foundation
import MaaCore
import OSLog
import SwiftyJSON

private let logger = Logger(subsystem: "plus.maa.swift", category: "MAAHandle")

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

private func handleAsst(msg: AsstId, detailsPtr: UnsafePointer<CChar>?, handlePtr: UnsafeMutableRawPointer?) {
    guard let handlePtr else {
        logger.error("handlePtr is nil")
        return
    }
    let handle = Unmanaged<MAAHandle>.fromOpaque(handlePtr).takeUnretainedValue()

    let details = detailsPtr.map(String.init(cString:))

    let json = details.map(JSON.init(parseJSON:)) ?? .null
    handle.send(message: .init(code: Int(msg), details: json))
}

actor MAAHandle {
    private var handle: AsstHandle!

    private let callbacks: AsyncStream<MaaMessage>
    private let callbackContinuation: AsyncStream<MaaMessage>.Continuation
    private var callbackTask: Task<Void, Never>!

    nonisolated let messages: AsyncStream<MaaMessage>
    private let messageContinuation: AsyncStream<MaaMessage>.Continuation
    private var pendingCalls = [AsstAsyncCallId: CheckedContinuation<JSON, Error>]()

    init(options: MAAInstanceOptions = [:]) async throws {
        (self.callbacks, self.callbackContinuation) = AsyncStream<MaaMessage>.makeStream()
        (self.messages, self.messageContinuation) = AsyncStream<MaaMessage>.makeStream()

        self.callbackTask = Task { [weak self, callbacks] in
            for await callback in callbacks {
                await self?.process(callback)
            }
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        handle = AsstCreateEx(handleAsst, selfPtr)

        for (key, value) in options {
            let success = AsstSetInstanceOption(handle, key.rawValue, value)
            guard success.isTrue else {
                throw MaaCoreError.setInstanceOptionFailed
            }
        }
    }

    deinit {
        AsstDestroy(handle)
        callbackTask?.cancel()
        callbackContinuation.finish()
        pendingCalls.forEach { $1.resume(throwing: CancellationError()) }
        messageContinuation.finish()
    }

    nonisolated func send(message: MaaMessage) {
        self.callbackContinuation.yield(message)
    }

    private func process(_ message: MaaMessage) {
        if message.code == 4 {
            // AsyncCallInfo
            let info = message.details
            guard let callID = info["async_call_id"].int32 else {
                logger.error("Invalid `async_call_id` in AsyncCallInfo: \(info)")
                return
            }
            guard let continuation = pendingCalls.removeValue(forKey: callID) else {
                logger.error("No pending call with ID: \(callID)")
                return
            }
            continuation.resume(returning: info)
            return
        }
        messageContinuation.yield(message)
    }

    private func waitFor(_ call: @autoclosure () -> AsstAsyncCallId) async throws -> JSON {
        try await withCheckedThrowingContinuation { continuation in
            let callID = call()
            guard callID != 0 else {
                continuation.resume(throwing: MaaCoreError.asyncCallFailed)
                return
            }
            pendingCalls[callID] = continuation
        }
    }

    func appendTask(type: MAATaskType, params: String) throws -> Int32 {
        let taskID = AsstAppendTask(handle, type.rawValue, params)
        if taskID == 0 {
            throw MaaCoreError.appendTaskFailed
        } else {
            return taskID
        }
    }

    func connect(adbPath: String, address: String, profile: String) async throws {
        let info = try await waitFor(AsstAsyncConnect(handle, adbPath, address, profile, 0))

        guard let ret = info["details"]["ret"].bool else {
            logger.error("Invalid `ret` in AsyncCallInfo: \(info)")
            throw MaaCoreError.connectFailed
        }

        guard ret else {
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
            let image = CGImage(
                pngDataProviderSource: provider, decode: nil,
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

enum MAATaskType: String {
    case StartUp
    case CloseDown
    case Recruit
    case Infrast
    case Fight
    case Mall
    case Award
    case Roguelike
    case Copilot
    case SSSCopilot
    case Depot
    case Reclamation
    case VideoRecognition
    case OperBox
    case Custom
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
    case asyncCallFailed
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

extension AsstBool {
    fileprivate var isTrue: Bool { self != 0 }
}

struct MAAResourceVersion: Codable {
    let activity: MAAResourceActivity
    let gacha: MAAResourceGacha
    let last_updated: String
}

struct MAAResourceActivity: Codable {
    let name: String
    let time: Date
}

struct MAAResourceGacha: Codable {
    let pool: String
    let time: Date
}

extension MAAResourceVersion {
    var title: String {
        if activity.time >= gacha.time {
            return activity.name
        } else {
            return gacha.pool
        }
    }
}
