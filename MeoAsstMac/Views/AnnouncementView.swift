import SwiftUI

struct AnnouncementMenuButton: View {
    @ObservedObject var store: AnnouncementStore
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button {
            openWindow(id: "community-announcements")
        } label: {
            Label(
                LocalizedStringKey(store.hasUnread ? "Announcement.Unread" : "Announcement.Title"),
                systemImage: store.hasUnread ? "text.bubble.fill" : "text.bubble")
        }
    }
}

struct AnnouncementView: View {
    @ObservedObject var store: AnnouncementStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Announcement.Title").font(.title2.bold())
            Text("Announcement.SourceNote").font(.callout).foregroundStyle(.secondary)
            if store.source.locale == "en" {
                Text("Announcement.LanguageNote").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Link("Announcement.Original", destination: store.source.url)
                Spacer()
                Button("Announcement.Refresh") { Task { await store.refresh(force: true) } }
                    .disabled(store.isRefreshing)
                if store.isRefreshing { ProgressView().controlSize(.small) }
            }
            Divider()
            if let announcement = store.announcement {
                ScrollView {
                    AnnouncementMarkdown(content: announcement.content)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .id(announcement.hash)
                .task(id: announcement.hash) { store.markDisplayed(hash: announcement.hash) }
                HStack {
                    Text("Announcement.FetchedAt")
                    Text(announcement.fetchedAt, style: .date)
                    Text(announcement.fetchedAt, style: .time)
                }
                .font(.caption).foregroundStyle(.secondary)
            } else {
                ContentUnavailableView(
                    "Announcement.Empty", systemImage: "text.bubble", description: Text("Announcement.EmptyHint"))
            }
            if let error = store.error { Text(error).font(.callout).foregroundStyle(.orange) }
            Toggle("Announcement.AutomaticallyShow", isOn: $store.automaticallyShow)
                .font(.callout)
        }
        .padding(20)
        .frame(minWidth: 480, idealWidth: 660, minHeight: 400, idealHeight: 580)
        .task { await store.refresh() }
        .environment(
            \.openURL,
            OpenURLAction { url in
                guard AnnouncementService.safeWebURL(url) else { return .discarded }
                return .systemAction(url)
            })
    }
}

/// Render text and user-clicked web links. Remote HTML and image URLs are never loaded or executed.
private struct AnnouncementMarkdown: View {
    let content: String
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(Array(content.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in
                if line.hasPrefix("# ") {
                    Text(inline(String(line.dropFirst(2)))).font(.title2.bold()).padding(.top, 8)
                } else if line.hasPrefix("## ") {
                    Text(inline(String(line.dropFirst(3)))).font(.headline).padding(.top, 6)
                } else if line.hasPrefix("### ") {
                    Text(inline(String(line.dropFirst(4)))).font(.subheadline.bold())
                } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                        Text(inline(String(line.dropFirst(2))))
                    }
                } else if !line.isEmpty {
                    Text(inline(line))
                } else {
                    Color.clear.frame(height: 4)
                }
            }
        }
    }

    private func inline(_ line: String) -> AttributedString {
        var text =
            (try? AttributedString(markdown: line, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(line)
        for run in text.runs {
            if let url = run.link, !AnnouncementService.safeWebURL(url) { text[run.range].link = nil }
        }
        return text
    }
}
