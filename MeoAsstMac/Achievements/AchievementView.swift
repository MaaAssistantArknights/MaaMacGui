import SwiftUI

struct AchievementView: View {
    @ObservedObject private var store = AchievementStore.shared
    @State private var onlyLocked = false
    @State private var confirmsReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Achievement.LocalNotice").font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("Achievement.OnlyLocked", isOn: $onlyLocked)
            Toggle("Achievement.UnlockHints", isOn: $store.showUnlockHints)
            if let message = store.message { Text(message).foregroundStyle(.orange) }
            List {
                ForEach(["basic", "roguelike", "copilot", "features"], id: \.self) { group in
                    Section(String(localized: String.LocalizationValue("Achievement.Group." + group))) {
                        ForEach(AchievementDefinition.all.filter { definition in
                            definition.groupID == group && (!onlyLocked || store.engine.state.progress[definition.id]?.unlockedAt == nil)
                        }) { definition in
                            row(definition)
                        }
                    }
                }
            }
            HStack {
                Text("Achievement.HistoryNotice").font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Achievement.Reset", role: .destructive) { confirmsReset = true }
            }
        }
        .padding()
        .confirmationDialog("Achievement.ConfirmReset", isPresented: $confirmsReset) {
            Button("Achievement.Reset", role: .destructive) { store.resetWithBackup() }
            Button("取消", role: .cancel) {}
        }
        .onAppear { store.record(.init(metric: .achievementView, operation: .maximum)) }
    }

    @ViewBuilder private func row(_ definition: AchievementDefinition) -> some View {
        let progress = store.engine.state.progress[definition.id] ?? AchievementProgress()
        let hidden = definition.hidden && progress.unlockedAt == nil
        HStack {
            Image(systemName: progress.unlockedAt == nil ? "seal" : "checkmark.seal.fill")
                .foregroundStyle(progress.unlockedAt == nil ? Color.secondary : Color.green)
            VStack(alignment: .leading, spacing: 4) {
                Text(hidden ? String(localized: "Achievement.Hidden") : definition.title).font(.headline)
                if !hidden {
                    Text(definition.condition).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ProgressView(value: Double(min(progress.value, definition.target)), total: Double(definition.target))
                    Text("\(progress.value) / \(definition.target)").font(.caption.monospacedDigit())
                }
                if let time = progress.unlockedAt { Text(time.formatted(date: .numeric, time: .shortened)).font(.caption) }
            }
        }
        .padding(.vertical, 4)
    }
}

struct AchievementUnlockHint: View {
    @ObservedObject private var store = AchievementStore.shared
    var body: some View {
        if store.showUnlockHints, !store.latestUnlocks.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Achievement.Unlocked").font(.caption).foregroundStyle(.secondary)
                    Text(store.latestUnlocks.compactMap { id in AchievementDefinition.all.first { $0.id == id }?.title }.joined(separator: ", "))
                        .font(.headline).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button { store.latestUnlocks = [] } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).padding(6)
                    .accessibilityLabel("Achievement.Dismiss")
            }
            .padding(12)
            .frame(maxWidth: 360)
            .fixedSize(horizontal: false, vertical: true)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding()
            .accessibilityElement(children: .contain)
        }
    }
}
