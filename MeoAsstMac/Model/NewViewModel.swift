//
//  NewViewModel.swift
//  MAA
//
//  Created by hguandl on 2026/8/8.
//

import Combine
import Foundation
import Observation

// TODO: Mirgrate all bridges
@Observable final class NewViewModel {
    private(set) var copilot = CopilotContext()

    /// A unique token that changes whenever a copilot task starts.
    ///
    /// Observe changes to this value to detect the start of a copilot task.
    private(set) var copilotStartToken: UUID?

    /// The progress of the current copilot download.
    ///
    /// A `nil` value indicates that no download is in progress.
    /// Progress is updated only for copilot sets, based on the number of copilots downloaded.
    ///
    /// Cancellation is not currently supported.
    private(set) var copilotDownloadProgress: Progress?

    /// The URL of the most recently imported copilot.
    ///
    /// Observe this value to update and select the corresponding list entry after an import.
    var lastImportedCopilot: URL?

    // MARK: - Bridges to Old View Model

    private let parent: MAAViewModel

    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    @MainActor var status: MAAViewModel.Status {
        access(keyPath: \.status)
        return parent.status
    }

    @MainActor init(parent: MAAViewModel) {
        self.parent = parent

        parent.$status.sink { [weak self] _ in
            self?.withMutation(keyPath: \.status) {}
        }
        .store(in: &cancellables)
    }
}

// MARK: - Copilot Bridges

extension NewViewModel {
    func stop() async throws {
        try await parent.stop()
    }

    func startCopilot() async throws {
        copilotStartToken = UUID()

        var config = copilot.config
        let type: MAATaskType

        if copilot.category == .list {
            guard let kind = copilot.copilotSet?.kind else {
                return
            }

            config.filename = nil
            config.copilot_list = copilot.copilotList.filter(\.isOn).map {
                .init(
                    filename: $0.url.path(percentEncoded: false),
                    nav_name_override: nil,
                    is_raid: $0.isRaid ?? false)
            }

            switch kind {
            case .regular:
                type = .Copilot
            case .sss:
                type = .SSSCopilot
            case .paradox:
                type = .ParadoxCopilot
            }
        } else {
            guard let url = copilot.url else {
                return
            }

            config.filename = url.path(percentEncoded: false)

            switch copilot.content {
            case .copilot(let kind, _):
                switch kind {
                case .regular:
                    type = .Copilot
                case .sss:
                    type = .SSSCopilot
                case .paradox:
                    type = .ParadoxCopilot
                }
            default:
                return
            }
        }

        guard let params = try? config.jsonString() else {
            return
        }

        try await parent.startCopilot(type: type, params: params)
    }

    func recognizeVideo(url: URL) async throws {
        try await parent.recognizeVideo(video: url)
    }
}

// MARK: - PRTS Copilot Downloader

extension NewViewModel {
    func downloadCopilot(code: PRTSCode) async {
        let progress = Progress()
        copilotDownloadProgress = progress
        defer { copilotDownloadProgress = nil }

        do {
            switch code {
            case .copilot(let id):
                lastImportedCopilot = try await MAACopilot.download(id: id, toDirectory: .externalCopilotDirectory)
            case .set(let setID):
                lastImportedCopilot = try await CopilotSetData.download(id: setID, progress: progress)
            }
        } catch {
            print(error)
        }
    }
}
