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

    func mapLevelCode(matching key: String) -> String? {
        let mapLevelKey = key.withCString {
            AsstGetMapLevelKey($0)
        }
        guard let code = mapLevelKey.code else {
            return nil
        }
        return String(cString: code)
    }
}

actor MAAHandle {
    private nonisolated(unsafe) var handle: AsstHandle!

    nonisolated let messages: AsyncStream<MaaMessage>
    private let continuation: AsyncStream<MaaMessage>.Continuation
    private var pendingCalls = [AsstAsyncCallId: CheckedContinuation<JSON, Error>]()

    init(options: MAAInstanceOptions = [:]) async throws {
        (messages, continuation) = AsyncStream<MaaMessage>.makeStream()

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        handle = AsstCreateEx(
            { msg, details, context in
                let data = details.map { Data(bytes: $0, count: strlen($0)) } ?? Data()
                let handle = Unmanaged<MAAHandle>.fromOpaque(context!).takeUnretainedValue()
                handle.process(msg: msg, details: data)
            }, selfPtr)

        for (key, value) in options {
            let success = AsstSetInstanceOption(handle, key.rawValue, value)
            guard success.isTrue else {
                throw MaaCoreError.setInstanceOptionFailed
            }
        }
    }

    deinit {
        AsstDestroy(handle)
        pendingCalls.forEach { $1.resume(throwing: CancellationError()) }
        continuation.finish()
    }

    private nonisolated func process(msg: AsstId, details: Data) {
        let info: JSON
        do {
            info = try JSON(data: details)
        } catch {
            logger.error("Failed to parse details: \(error)")
            return
        }
        if msg == 4 {
            // AsyncCallInfo
            guard let callID = info["async_call_id"].int32 else {
                logger.error("Invalid `async_call_id` in AsyncCallInfo: \(info)")
                return
            }
            Task {
                await resumeCall(for: callID, info: info)
            }
            return
        }
        continuation.yield(.init(code: Int(msg), details: info))
    }

    private func resumeCall(for id: AsstAsyncCallId, info: JSON) {
        guard let continuation = pendingCalls.removeValue(forKey: id) else {
            logger.error("No pending call with ID: \(id)")
            return
        }
        continuation.resume(returning: info)
    }

    private func waitFor(_ call: @autoclosure () -> AsstAsyncCallId) async throws -> JSON {
        try await withCheckedThrowingContinuation { continuation in
            let callID = call()
            guard callID != 0 else {
                continuation.resume(throwing: MaaCoreError.asyncCallFailed)
                return
            }
            guard !pendingCalls.keys.contains(callID) else {
                fatalError("Duplicated pending calls")
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
    case ParadoxCopilot
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

struct MAAStageActivity: Decodable, Hashable {
    let miniGame: [MiniGame]

    struct MiniGame: Decodable, Hashable {
        let Display: String?
        let DisplayKey: String?
        let Value: String
        let Tip: String?
        let TipKey: String?
        let MinimumRequired: String?
        private let UtcStartTime: String?
        private let UtcExpireTime: String?
        private let TimeZone: Double?
    }
}

extension MAAStageActivity.MiniGame {
    var startTime: Date {
        if let value = UtcStartTime, let date = try? dateParser?.parse(value) {
            return date
        } else {
            return .distantPast
        }
    }

    var expireTime: Date {
        if let value = UtcExpireTime, let date = try? dateParser?.parse(value) {
            return date
        } else {
            return .distantFuture
        }
    }

    private var dateParser: Date.ParseStrategy? {
        guard let TimeZone else { return nil }
        return .init(
            format:
                "\(year: .defaultDigits)/\(month: .twoDigits)/\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)",
            timeZone: .init(secondsFromGMT: Int(TimeZone * 3600))!)
    }
}
