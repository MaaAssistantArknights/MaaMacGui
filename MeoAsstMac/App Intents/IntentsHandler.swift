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
        let respond = RunMAAIntentResponse(code: .success, userActivity: nil)
        Task { @MainActor in
            viewModel?.dailyTasksDetailMode = .log
            await viewModel?.tryStartTasks()
        }
        completion(respond)
    }
}

class StopMAAIntentHandler: NSObject, StopMAAIntentHandling {
    weak var viewModel: MAAViewModel?

    init(viewModel: MAAViewModel?) {
        self.viewModel = viewModel
    }

    func handle(intent: StopMAAIntent, completion: @escaping (StopMAAIntentResponse) -> Void) {
        let respond = StopMAAIntentResponse(code: .success, userActivity: nil)
        Task { @MainActor in
            try await viewModel?.stop()
        }
        completion(respond)
    }
}
