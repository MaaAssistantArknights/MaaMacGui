//
//  IntentsHandler.swift
//  MAA
//
//  Created by 罗板栗 on 2025/4/29.
//

import Foundation
import SwiftUI
import Intents

class RunMAAIntentHandler: NSObject, RunMAAIntentHandling {
    weak var viewModel: MAAViewModel?

    init(viewModel: MAAViewModel?) {
        self.viewModel = viewModel
    }

    func handle(intent: RunMAAIntent, completion: @escaping (RunMAAIntentResponse) -> Void) {
        Task { @MainActor in
            viewModel?.dailyTasksDetailMode = .log
            await viewModel?.tryStartTasks()
            return RunMAAIntentResponseCode.success
        }
    }
}

class StopMAAIntentHandler: NSObject, StopMAAIntentHandling {
    weak var viewModel: MAAViewModel?

    init(viewModel: MAAViewModel?) {
        self.viewModel = viewModel
    }

    func handle(intent: StopMAAIntent, completion: @escaping (StopMAAIntentResponse) -> Void) {
        Task { @MainActor in
            try await viewModel?.stop()
            return StopMAAIntentResponseCode.success
        }
    }
}
