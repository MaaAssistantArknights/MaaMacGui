//
//  RecruitSettingsView.swift
//  MeoAsstMac
//
//  Created by hguandl on 9/10/2022.
//

import SwiftUI

struct RecruitSettingsView: View {
    @Binding var config: RecruitConfiguration
    /// Effective resource directory; the bundle is only a fallback when nil.
    var resourceDirectory: URL? = nil
    /// Modification date of the effective tag table; changes on in-place resource updates.
    var resourceRevision: Date? = nil
    @Environment(\.locale) private var locale
    @State private var catalog = RecruitTagCatalog(labels: [:])

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("自动刷新3星Tags", isOn: $config.refresh)

                Toggle("自动使用加急许可", isOn: $config.expedite)

                Toggle("3星设置7:40而非9:00", isOn: level3UseShortTime)

                Stepper(value: $config.times, in: 0...1000) {
                    HStack {
                        Text("每次执行时最大招募次数: ")
                        TextField("", value: $config.times, format: .number)
                            .frame(maxWidth: 50)
                    }
                }

                tagList(
                    title: "3星首选标签", enabled: $config.first_tags_enabled, tags: $config.first_tags,
                    hint: "仅影响3星标签选择，不改变高星确认规则。")
                tagList(
                    title: "保留标签", enabled: $config.preserve_tags_enabled, tags: $config.preserve_tags,
                    hint: "命中任一保留标签时跳过该槽位，不自动招募。")
                Toggle("自动确认3星", isOn: autoConfirm(level: 3))
                Toggle("自动确认4星", isOn: autoConfirm(level: 4))
                Toggle("自动确认5星", isOn: autoConfirm(level: 5))
                Toggle("自动确认6星", isOn: .constant(false)).disabled(true)
            }
            .padding()
        }
        .task(id: reloadToken) {
            let directory = resourceDirectory ?? Bundle.main.resourceURL?.appendingPathComponent("resource")
            let language = locale.language.languageCode?.identifier ?? "zh"
            let loaded = await Task.detached {
                RecruitTagCatalog.load(resourceDirectory: directory, languageCode: language)
            }.value
            // A reload superseded by a token change must not overwrite the newer catalog.
            guard !Task.isCancelled else { return }
            catalog = loaded
        }
    }

    /// Locale switches, directory changes and in-place table updates all reload the catalog.
    private var reloadToken: String {
        locale.identifier + (resourceDirectory?.path ?? "") + "\(resourceRevision?.timeIntervalSince1970 ?? 0)"
    }

    @ViewBuilder private func tagList(
        title: LocalizedStringKey, enabled: Binding<Bool>, tags: Binding<[String]>, hint: LocalizedStringKey
    ) -> some View {
        let availableTags = catalog.tags.filter { !tags.wrappedValue.contains($0) }
        VStack(alignment: .leading, spacing: 6) {
            Toggle(title, isOn: enabled)
            Text(hint).font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                ForEach(Array(tags.wrappedValue.enumerated()), id: \.offset) { index, tag in
                    HStack {
                        Text(catalog.label(for: tag))
                        Spacer()
                        Button {
                            tags.wrappedValue.swapAt(index, index - 1)
                        } label: {
                            Image(systemName: "arrow.up")
                        }
                        .disabled(index == 0)
                        .accessibilityLabel("上移标签")
                        Button {
                            tags.wrappedValue.swapAt(index, index + 1)
                        } label: {
                            Image(systemName: "arrow.down")
                        }
                        .disabled(index == tags.wrappedValue.count - 1)
                        .accessibilityLabel("下移标签")
                        Button {
                            tags.wrappedValue.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .accessibilityLabel("移除标签")
                    }
                }
                Menu("添加标签") {
                    ForEach(availableTags, id: \.self) { tag in
                        Button(catalog.label(for: tag)) {
                            tags.wrappedValue = RecruitConfiguration.normalizedTags(tags.wrappedValue + [tag])
                        }
                    }
                }
                .disabled(availableTags.isEmpty)
                if catalog.tags.isEmpty {
                    Text("无法读取公招标签资源，已保存的标签仍会保留。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .disabled(!enabled.wrappedValue)
        }
    }

    private var level3UseShortTime: Binding<Bool> {
        Binding {
            config.recruitment_time["3"] == 460
        } set: { newValue in
            if newValue {
                config.recruitment_time["3"] = 460
            } else {
                config.recruitment_time["3"] = 540
            }
        }
    }

    private func autoConfirm(level: Int) -> Binding<Bool> {
        Binding {
            config.confirm.contains(level)
        } set: { newValue in
            if newValue {
                var levels = Set(config.confirm)
                levels.insert(level)
                config.confirm = levels.sorted()
            } else {
                config.confirm.removeAll { $0 == level }
            }
        }
    }
}

struct RecruitSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        RecruitSettingsView(config: .constant(.init()))
    }
}
