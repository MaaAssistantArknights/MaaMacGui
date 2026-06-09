import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension MAAViewModel {

    // MARK: - Remote Control Types

    struct RemoteTask: Codable {
        let id: String
        let type: String
        let params: String?
    }

    struct RemoteTaskRequest: Codable {
        let user: String
        let device: String
    }

    struct RemoteTaskResponse: Codable {
        let tasks: [RemoteTask]?
    }

    struct TaskStatusReport: Codable {
        let user: String
        let device: String
        let status: String
        let task: String
        let payload: String?
    }

    enum RemoteControlError: LocalizedError {
        case emptyEndpoint
        case invalidURL
        case connectionFailed(String)
        case invalidResponse
        case missingTaskParams
        case invalidTaskType
        case unsupportedVariantType

        var errorDescription: String? {
            switch self {
            case .emptyEndpoint:
                return "远程控制端点为空"
            case .invalidURL:
                return "无效的远程控制URL"
            case .connectionFailed(let reason):
                return "连接失败: \(reason)"
            case .invalidResponse:
                return "远程控制服务器响应无效"
            case .missingTaskParams:
                return "缺少远端任务参数"
            case .invalidTaskType:
                return "无效远端任务类型"
            case .unsupportedVariantType:
                return "不支持的LinkStart任务类型"
            }
        }
    }

    // MARK: - Variables

    private static var completedTaskIds: Set<String> = []
    private static var enqueuedTaskIds: Set<String> = []
    private static var executeSequentialRemoteTask: Task<Void, Never>? = nil
    private static var executeInstantRemoteTask: Task<Void, Never>? = nil
    private static var remoteControlPollingTask: Task<Void, Never>? = nil
    private static var remoteControlCancellables = Set<AnyCancellable>()
    private static var sequentialTaskPublisher = PassthroughSubject<RemoteTask, Never>()
    private static var instantTaskPublisher = PassthroughSubject<RemoteTask, Never>()
    private static var sequentialTaskQueue: [RemoteTask] = []
    private static var instantTaskQueue: [RemoteTask] = []
    private static var currentRemoteTask: RemoteTask? = nil

    // MARK: - Remote Control

    func testRemoteControlConnection() async throws -> Bool {
        guard !remoteControlGetTaskEndpointUri.isEmpty else {
            throw RemoteControlError.emptyEndpoint
        }

        guard let url = URL(string: remoteControlGetTaskEndpointUri) else {
            throw RemoteControlError.invalidURL
        }

        let request = RemoteTaskRequest(
            user: remoteControlUserIdentity,
            device: remoteControlDeviceIdentity
        )

        do {
            let (_, response) = try await fetch(to: url, with: request)

            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }

            return false
        } catch {
            throw RemoteControlError.connectionFailed(error.localizedDescription)
        }
    }

    func startRemoteControl() {
        guard !remoteControlGetTaskEndpointUri.isEmpty else { return }

        stopRemoteControlPolling()

        if Self.executeSequentialRemoteTask == nil {
            Self.executeSequentialRemoteTask = Task { [weak self] in
                guard let self else { return }
                
                var taskStatus: String? = nil
                var taskPayload: String? = nil
                while !Task.isCancelled {
                    await self.waitUntilIdle()
                    // defer the status report until the status becomes idle again
                    if Self.currentRemoteTask != nil {
                        let id = Self.currentRemoteTask!.id
                        await reportTaskStatus(taskId: id, status: taskStatus!, payload: taskPayload)
                        Self.currentRemoteTask = nil
                        // sleep for 1 second to avoid errors
                        try! await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                    let task = await self.waitForNewTask(Self.sequentialTaskPublisher, &Self.sequentialTaskQueue)
                    guard self.status == .idle else { continue }
                    Self.currentRemoteTask = task
                    (taskStatus, taskPayload) = await self.executeRemoteTask(task)
                }
            }
        }

        if Self.executeInstantRemoteTask == nil {
            Self.executeInstantRemoteTask = Task { [weak self] in
                guard let self else { return }

                while !Task.isCancelled {
                    let task = await self.waitForNewTask(Self.instantTaskPublisher, &Self.instantTaskQueue)
                    let (taskStatus, taskPayload) = await self.executeRemoteTask(task)
                    await reportTaskStatus(taskId: task.id, status: taskStatus, payload: taskPayload)
                }
            }
        }

        if Self.remoteControlPollingTask == nil {
            Self.remoteControlPollingTask = Task {
                while true {
                    do {
                        try await pollRemoteTaskLoop()
                        try await Task.sleep(nanoseconds: UInt64(remoteControlPollIntervalMs) * 1_000_000)
                    } catch {
                        try? await Task.sleep(nanoseconds: UInt64(remoteControlPollIntervalMs) * 1_000_000)
                    }
                }
            }
        }
    }

    func stopRemoteControlPolling() {
        Self.remoteControlPollingTask?.cancel()
        Self.remoteControlPollingTask = nil
        Self.executeSequentialRemoteTask?.cancel()
        Self.executeSequentialRemoteTask = nil
        Self.executeInstantRemoteTask?.cancel()
        Self.executeInstantRemoteTask = nil
        Self.remoteControlCancellables.removeAll()
    }

    private func pollRemoteTaskLoop() async throws {
        guard !remoteControlGetTaskEndpointUri.isEmpty else {
            throw RemoteControlError.emptyEndpoint
        }

        guard let url = URL(string: remoteControlGetTaskEndpointUri) else {
            throw RemoteControlError.invalidURL
        }

        let request = RemoteTaskRequest(
            user: remoteControlUserIdentity,
            device: remoteControlDeviceIdentity
        )

        let (data, response) = try await fetch(to: url, with: request)

        guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200
        else {
            throw RemoteControlError.invalidResponse
        }

        let taskResponse = try JSONDecoder().decode(RemoteTaskResponse.self, from: data)

        if let tasks = taskResponse.tasks {
            for task in tasks {
                let taskType = task.type
                let taskId = task.id

                if Self.enqueuedTaskIds.contains(taskId) {
                    continue
                }

                Self.enqueuedTaskIds.insert(taskId)

                switch taskType {
                case "LinkStart",
                    "LinkStart-Base",
                    "LinkStart-WakeUp",
                    "LinkStart-Combat",
                    "LinkStart-Recruiting",
                    "LinkStart-Mall",
                    "LinkStart-Mission",
                    "LinkStart-AutoRoguelike",
                    "LinkStart-Reclamation",
                    "Toolbox-GachaOnce",
                    "Toolbox-GachaTenTimes",
                    "CaptureImage",
                    "Settings-ConnectAddress",
                    "Settings-Stage1":
                    Self.sequentialTaskQueue.append(task)
                    Self.sequentialTaskPublisher.send(task)

                case "CaptureImageNow",
                    "HeartBeat",
                    "StopTask":
                    Self.instantTaskQueue.append(task)
                    Self.instantTaskPublisher.send(task)

                default:
                    logError("未知的远端任务类型: \(taskType)")
                }
            }
        }
    }

    private func executeRemoteTask(_ task: RemoteTask) async -> (String, String?) {
        let taskType = task.type
        let taskId = task.id

        var taskStatus = "SUCCESS"
        var taskPayload: String? = nil

        do {
            switch taskType {
            case "LinkStart":
                await tryStartTasks()

            case "LinkStart-Base",
                "LinkStart-WakeUp",
                "LinkStart-Combat",
                "LinkStart-Recruiting",
                "LinkStart-Mall",
                "LinkStart-Mission",
                "LinkStart-AutoRoguelike",
                "LinkStart-Reclamation":
                try await linkStart(variant: taskType.replacingOccurrences(of: "LinkStart-", with: ""))

            case "Toolbox-GachaOnce":
                try await gachaPoll(once: true)

            case "Toolbox-GachaTenTimes":
                try await gachaPoll(once: false)

            case "CaptureImage":
                try await ensureHandle(clearLogs: false)
                taskPayload = try await handle?.getImage().base64EncodedString

            case "CaptureImageNow":
                // don't ensureHandle for instant image capture
                taskPayload = try await handle?.getImage().base64EncodedString

            case "Settings-ConnectAddress":
                guard let newAddress = task.params else {
                    throw RemoteControlError.missingTaskParams
                }

                connectionAddress = newAddress
                logTrace("连接地址已更新为: \(newAddress)")

            case "Settings-Stage1":
                // not implemented
                throw RemoteControlError.invalidTaskType

            case "HeartBeat":
                taskPayload = Self.currentRemoteTask?.id ?? ""

            case "StopTask":
                try await stop()

            default:
                logError("未知的远端任务类型: \(taskType)")
                taskStatus = "FAILED"
            }
        } catch {
            taskStatus = "FAILED"
            logError("执行远端任务 \(taskId) 失败: \(error.localizedDescription)")
        }

        Self.completedTaskIds.insert(taskId)
        
        return (taskStatus, taskPayload)
    }

    private func reportTaskStatus(taskId: String, status: String, payload: String?) async {
        guard !remoteControlReportStatusUri.isEmpty else { return }
        guard let url = URL(string: remoteControlReportStatusUri) else { return }
        
        let report = TaskStatusReport(
            user: remoteControlUserIdentity,
            device: remoteControlDeviceIdentity,
            status: status,
            task: taskId,
            payload: payload
        )

        do {
            let _ = try await fetch(to: url, with: report)
        } catch {
            logError("报告任务状态失败: \(error.localizedDescription)")
        }
    }

    // MARK: - Utils

    private func fetch<T: Codable>(to url: URL, with body: T) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let jsonData = try JSONEncoder().encode(body)
        request.httpBody = jsonData

        return try await URLSession.shared.data(for: request)
    }

    func waitUntilIdle() async {
        await withCheckedContinuation { continuation in
            var cancellable: AnyCancellable?
            cancellable =
                $status
                .filter { $0 == .idle }
                .first()
                .sink { _ in
                    cancellable?.cancel()
                    continuation.resume()
                }
        }
    }

    private func waitForNewTask(_ publisher: PassthroughSubject<RemoteTask, Never>, _ queue: inout [RemoteTask]) async -> RemoteTask {
        await withCheckedContinuation { continuation in
            if !queue.isEmpty {
                queue.removeAll { Self.completedTaskIds.contains($0.id) }
                let task = queue.first
                if task != nil {
                    continuation.resume(returning: task!)
                    return
                }
            }

            var cancellable: AnyCancellable?
            cancellable =
                publisher
                .filter { !Self.completedTaskIds.contains($0.id) }
                .first()
                .sink { value in
                    cancellable?.cancel()
                    continuation.resume(returning: value)
                }
        }
    }
}

// MARK: - CGImage Base64 Support

extension CGImage {
    var jpegData: Data? {
        guard let mutableData = CFDataCreateMutable(nil, 0),
            let destination = CGImageDestinationCreateWithData(mutableData, UTType.jpeg.identifier as CFString, 1, nil)
        else {
            return nil
        }
        CGImageDestinationAddImage(destination, self, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }

    var base64EncodedString: String {
        return self.jpegData?.base64EncodedString() ?? ""
    }
}
