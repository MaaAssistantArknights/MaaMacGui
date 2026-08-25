//
//  PRTSPlusSearchView.swift
//  MAA
//

import SwiftUI

struct PRTSPlusSearchView: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    @Environment(NewViewModel.self) private var newModel
    @Environment(\.dismiss) private var dismiss

    @State private var stage = ""
    @State private var operatorQuery = ""
    @State private var operatorQueryMode = OperatorQueryMode.all
    @State private var matchFilter = MatchFilter.all
    @State private var squadFilter = SquadFilter.all
    @State private var sortOrder = SortOrder.recommended
    @State private var results = [PRTSPlusSearchResult]()
    @State private var searching = false
    @State private var importingIDs = Set<Int>()
    @State private var importedIDs = Set<Int>()
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            Divider()

            if !results.isEmpty {
                filterBar
                Divider()
            }

            content
        }
        .frame(minWidth: 780, minHeight: 560)
        .navigationTitle("搜索 PRTS.plus 作业")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("完成") {
                    dismiss()
                }
            }
        }
        .alert("操作失败", isPresented: showErrorAlert) {
            Button("好") {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var searchBar: some View {
        HStack {
            TextField("关卡代号，例如 1-7 或 main_01-07", text: $stage)
                .textFieldStyle(.roundedBorder)
                .onSubmit(search)
            Button(action: search) {
                if searching {
                    ProgressView().controlSize(.small)
                } else {
                    Label("搜索", systemImage: "magnifyingglass")
                }
            }
            .disabled(searching || normalizedStage.isEmpty)
        }
        .padding()
    }

    private var filterBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                TextField("多个干员用空格或逗号分隔", text: $operatorQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 180, maxWidth: .infinity)

                Picker("干员条件", selection: $operatorQueryMode) {
                    ForEach(OperatorQueryMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()

                Picker("匹配", selection: $matchFilter) {
                    ForEach(MatchFilter.allCases, id: \.self) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
                .disabled(ownedOperators == nil)
                .help(ownedOperators == nil ? "完成一次干员识别后可使用匹配筛选" : "按已识别的干员筛选")
            }

            HStack(spacing: 12) {
                Picker("编队位", selection: $squadFilter) {
                    ForEach(SquadFilter.allCases, id: \.self) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()

                Picker("排序", selection: $sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Text(order.title).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()

                Spacer(minLength: 8)

                if ownedOperators == nil {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .foregroundStyle(.secondary)
                        .help("尚无干员识别结果")
                }

                Text("\(filteredResults.count) / \(results.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 70, alignment: .trailing)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder private var content: some View {
        if searching && results.isEmpty {
            ProgressView("正在搜索全部作业…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, results.isEmpty {
            ContentUnavailableView(
                "搜索失败",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if results.isEmpty {
            ContentUnavailableView(
                "按关卡搜索作业",
                systemImage: "doc.text.magnifyingglass",
                description: Text("输入游戏内显示的关卡代号或作业中的 stage_name")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredResults.isEmpty {
            ContentUnavailableView {
                Label("没有符合筛选条件的作业", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("尝试更换干员、编队位或匹配条件")
            } actions: {
                Button("清除筛选", action: resetFilters)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(filteredResults) { result in
                PRTSPlusSearchResultRow(
                    result: result,
                    match: result.match(ownedOperators: ownedOperators),
                    importing: importingIDs.contains(result.id),
                    imported: importedIDs.contains(result.id),
                    canAddToList: newModel.copilot.copilotSet != nil
                ) {
                    importCopilot(result, addToList: $0)
                }
            }
            .listStyle(.inset)
        }
    }

    private var normalizedStage: String {
        stage.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var operatorQueries: [String] {
        let separators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ",，、;；"))

        return
            operatorQuery
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }
    }

    private var ownedOperators: [MAAOperBox.OwnedOper]? {
        guard let operBox = viewModel.operBox, operBox.done else { return nil }
        return operBox.own_opers
    }

    private var filteredResults: [PRTSPlusSearchResult] {
        results.filter { result in
            let matchesOperator: Bool
            switch operatorQueryMode {
            case .all:
                matchesOperator = operatorQueries.allSatisfy(result.containsOperator)
            case .any:
                matchesOperator = operatorQueries.isEmpty || operatorQueries.contains(where: result.containsOperator)
            }
            let matchesSquad = squadFilter.maximum.map { result.operatorCount <= $0 } ?? true
            let rosterMatch = result.match(ownedOperators: ownedOperators)
            let matchesRoster: Bool
            switch matchFilter {
            case .all:
                matchesRoster = true
            case .matched:
                matchesRoster = rosterMatch.state == .matched
            case .missing:
                matchesRoster = rosterMatch.state == .missing
            }
            return matchesOperator && matchesSquad && matchesRoster
        }
        .sorted(by: resultComparator)
    }

    private func resultComparator(_ lhs: PRTSPlusSearchResult, _ rhs: PRTSPlusSearchResult) -> Bool {
        switch sortOrder {
        case .recommended:
            let lhsMatch = lhs.match(ownedOperators: ownedOperators)
            let rhsMatch = rhs.match(ownedOperators: ownedOperators)
            if lhsMatch.state != rhsMatch.state {
                return lhsMatch.state.rawValue < rhsMatch.state.rawValue
            }
            if lhsMatch.missingSlots.count != rhsMatch.missingSlots.count {
                return lhsMatch.missingSlots.count < rhsMatch.missingSlots.count
            }
        case .hot:
            if lhs.hotScore != rhs.hotScore {
                return lhs.hotScore > rhs.hotScore
            }
        case .likes:
            if lhs.likes != rhs.likes {
                return lhs.likes > rhs.likes
            }
        case .fewestOperators:
            if lhs.operatorCount != rhs.operatorCount {
                return lhs.operatorCount < rhs.operatorCount
            }
        }

        if lhs.hotScore != rhs.hotScore {
            return lhs.hotScore > rhs.hotScore
        }
        if lhs.likes != rhs.likes {
            return lhs.likes > rhs.likes
        }
        return lhs.id > rhs.id
    }

    private var showErrorAlert: Binding<Bool> {
        Binding(
            get: { errorMessage != nil && !results.isEmpty },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func resetFilters() {
        operatorQuery = ""
        operatorQueryMode = .all
        matchFilter = .all
        squadFilter = .all
    }

    private func search() {
        guard !normalizedStage.isEmpty else { return }
        searching = true
        errorMessage = nil
        results = []
        Task {
            defer { searching = false }
            do {
                results = try await PRTSPlusSearchClient.search(stage: normalizedStage)
                if results.isEmpty {
                    errorMessage = String(localized: "没有找到该关卡的可用作业")
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func importCopilot(_ result: PRTSPlusSearchResult, addToList: Bool) {
        guard importingIDs.insert(result.id).inserted else { return }
        errorMessage = nil
        Task {
            defer { importingIDs.remove(result.id) }
            do {
                let url = try await MAACopilot.download(id: result.id, toDirectory: .externalCopilotDirectory)
                if addToList {
                    guard await newModel.copilot.appendCopilot(at: url) else {
                        throw PRTSPlusSearchClient.Error.incompatibleList
                    }
                } else {
                    newModel.lastImportedCopilot = url
                }
                importedIDs.insert(result.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - SearchResultRow

private struct PRTSPlusSearchResultRow: View {
    let result: PRTSPlusSearchResult
    let match: PRTSPlusSearchResult.RosterMatch
    let importing: Bool
    let imported: Bool
    let canAddToList: Bool
    let importCopilot: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(result.title)
                        .font(.headline)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    matchStatus
                }

                metadata

                if !result.operators.isEmpty {
                    requirementLine(
                        title: "固定干员",
                        systemImage: "person.2.fill",
                        text: result.operators.map(\.description).joined(separator: " · "))
                }

                ForEach(result.groups, id: \.name) { group in
                    groupLine(group)
                }

                if match.state == .missing {
                    Label("缺少：\(match.missingSlots.joined(separator: "、"))", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }

                if let details = result.details, !details.isEmpty {
                    Text(details)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            importControls
        }
        .padding(.vertical, 6)
    }

    private var metadata: some View {
        HStack(spacing: 12) {
            Label {
                Text(verbatim: result.uploader)
            } icon: {
                Image(systemName: "person")
            }
            Label("\(result.operatorCount) 位", systemImage: "person.2")
            Label {
                Text(verbatim: String(result.likes))
            } icon: {
                Image(systemName: "hand.thumbsup")
            }
            Label {
                Text(verbatim: String(result.views))
            } icon: {
                Image(systemName: "eye")
            }
            if let difficulty = result.difficulty {
                Label("难度 \(difficulty)", systemImage: "gauge.with.dots.needle.33percent")
            }
            if let version = result.minimumRequired, !version.isEmpty {
                Label(version, systemImage: "shippingbox")
            }
            Text(verbatim: "#\(result.id)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .help(result.stageName)
    }

    private func requirementLine(title: String, systemImage: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
            Text(text)
                .textSelection(.enabled)
        }
        .font(.caption)
    }

    private func groupLine(_ group: PRTSPlusSearchResult.OperatorGroup) -> some View {
        let text: String
        if let selectedName = match.groupSelections[group.name],
            let selected = group.operators.first(where: { $0.name == selectedName })
        {
            text = selected.description
        } else {
            let visible = group.operators.prefix(3).map(\.description).joined(separator: "、")
            let remaining = group.operators.count - min(group.operators.count, 3)
            text = remaining > 0 ? "\(visible) 等 \(group.operators.count) 名" : visible
        }

        return requirementLine(
            title: group.name,
            systemImage: match.groupSelections[group.name] == nil ? "person.2.badge.questionmark" : "checkmark.circle",
            text: text
        )
        .help(group.operators.map(\.description).joined(separator: "\n"))
    }

    @ViewBuilder private var matchStatus: some View {
        switch match.state {
        case .matched:
            Label("干员齐全", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .missing:
            Label("缺 \(match.missingSlots.count) 项", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
        case .unknown:
            Label("未匹配", systemImage: "circle.dashed")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var importControls: some View {
        if importing {
            ProgressView()
                .controlSize(.small)
                .frame(width: 92, height: 56)
        } else if imported {
            Label("已导入", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 92, height: 56)
        } else {
            VStack(alignment: .trailing) {
                Button {
                    importCopilot(false)
                } label: {
                    Label("下载", systemImage: "arrow.down.doc")
                }
                Button {
                    importCopilot(true)
                } label: {
                    Label("加入列表", systemImage: "text.badge.plus")
                }
                .disabled(!canAddToList)
                .help(canAddToList ? "加入列表" : "需要先激活一个作业集")
            }
            .frame(width: 92)
        }
    }
}

extension PRTSPlusSearchView {
    fileprivate enum OperatorQueryMode: CaseIterable {
        case all
        case any

        var title: String {
            switch self {
            case .all: String(localized: "全部包含")
            case .any: String(localized: "任意包含")
            }
        }
    }

    fileprivate enum MatchFilter: CaseIterable {
        case all
        case matched
        case missing

        var title: String {
            switch self {
            case .all: String(localized: "全部")
            case .matched: String(localized: "干员齐全")
            case .missing: String(localized: "有缺失")
            }
        }
    }

    fileprivate enum SquadFilter: CaseIterable {
        case all
        case upToThree
        case upToSix
        case upToTwelve

        var maximum: Int? {
            switch self {
            case .all: nil
            case .upToThree: 3
            case .upToSix: 6
            case .upToTwelve: 12
            }
        }

        var title: String {
            switch self {
            case .all: String(localized: "全部编队")
            case .upToThree: String(localized: "3 位以内")
            case .upToSix: String(localized: "6 位以内")
            case .upToTwelve: String(localized: "12 位以内")
            }
        }
    }

    fileprivate enum SortOrder: CaseIterable {
        case recommended
        case hot
        case likes
        case fewestOperators

        var title: String {
            switch self {
            case .recommended: String(localized: "推荐排序")
            case .hot: String(localized: "热度最高")
            case .likes: String(localized: "点赞最多")
            case .fewestOperators: String(localized: "干员最少")
            }
        }
    }
}

#Preview {
    let viewModel = MAAViewModel()
    NavigationStack {
        PRTSPlusSearchView()
    }
    .environmentObject(viewModel)
    .environment(NewViewModel(parent: viewModel))
}
