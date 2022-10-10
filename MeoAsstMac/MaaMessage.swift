//
//  MaaMessage.swift
//  MeoAsstMac
//
//  Created by hguandl on 9/10/2022.
//

import Foundation

enum MaaMessage: Decodable, CustomStringConvertible {
    /// - Tag: Global Info = 0
    case internalError
    case initFailed(InitFailedDetails)
    case connectionInfo(ConnectionInfoDetails)
    case allTasksCompleted(AllTasksCompletedDetails)

    /// - Tag: TaskChain Info = 10000
    case taskChainError
    case taskChainStart(TaskChainStartDetails)
    case taskChainCompleted(TaskChainCompletedDetails)
    case taskChainExtraInfo

    /// - Tag: SubTask Info = 20000
    case subTaskError
    case subTaskStart
    case subTaskCompleted
    case subTaskExtraInfo

    case unknown

    init(msg: Int32, details: String) {
        let data = details.data(using: .utf8)!
        switch Int(msg) {
        case 0:
            self = .internalError
        case 1:
            let details = try! JSONDecoder().decode(InitFailedDetails.self, from: data)
            self = .initFailed(details)
        case 2:
            let details = try! JSONDecoder().decode(ConnectionInfoDetails.self, from: data)
            self = .connectionInfo(details)
        case 3:
            let details = try! JSONDecoder().decode(AllTasksCompletedDetails.self, from: data)
            self = .allTasksCompleted(details)
        case 10000:
            self = .taskChainError
        case 10001:
            let details = try! JSONDecoder().decode(TaskChainStartDetails.self, from: data)
            self = .taskChainStart(details)
        case 10002:
            let details = try! JSONDecoder().decode(TaskChainCompletedDetails.self, from: data)
            self = .taskChainCompleted(details)
        case 10003:
            self = .taskChainExtraInfo
        case 20000:
            self = .subTaskError
        case 20001:
            self = .subTaskStart
        case 20002:
            self = .subTaskCompleted
        case 20003:
            self = .subTaskExtraInfo
        default:
            self = .unknown
        }
    }

    var description: String {
        switch self {
        case .internalError:
            return "internal error"
        case .initFailed(let initFailedDetails):
            return "initFailed: \(initFailedDetails.why)"
        case .connectionInfo(let connectionInfoDetails):
            return "connectionInfo: \(connectionInfoDetails.why)"
        case .allTasksCompleted(_):
            return "全部任务已完成"
        case .taskChainError:
            return "taskChainError"
        case .taskChainStart(let details):
            return "任务开始: \(details.taskchain)"
        case .taskChainCompleted(let details):
            return "任务完成: \(details.taskchain)"
        case .taskChainExtraInfo:
            return "taskChainExtraInfo"
        case .subTaskError:
            return "subTaskError"
        case .subTaskStart:
            return "subTaskStart"
        case .subTaskCompleted:
            return "subTaskCompleted"
        case .subTaskExtraInfo:
            return "subTaskExtraInfor"
        case .unknown:
            return "Unknown message"
        }
    }
}

struct InitFailedDetails: Decodable {
    let what: String
    let why: String
}

struct ConnectionInfoDetails: Decodable {
    let what: String
    let why: String
    let uuid: String
}

struct AllTasksCompletedDetails: Decodable {
    let taskchain: String
    let uuid: String
    let finished_tasks: [Int]
}

struct TaskChainStartDetails: Decodable {
    let uuid: String
    let taskchain: String
    let taskid: Int
}

typealias TaskChainCompletedDetails = TaskChainStartDetails
