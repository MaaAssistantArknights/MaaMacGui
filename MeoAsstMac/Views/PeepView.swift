import SwiftUI

struct PeepView: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    @Environment(\.displayScale) private var displayScale
    @StateObject private var preview = PeepViewModel()
    @State private var automatic = false
    @State private var displaySize = CGSize.zero

    /// A preview only needs as many pixels as its own area times the backing scale.
    private var maxPixelSize: Int? {
        let longest = max(displaySize.width, displaySize.height) * displayScale
        return longest > 0 ? Int(longest.rounded(.up)) : nil
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Toggle("Peep.Automatic", isOn: $automatic)
                    .toggleStyle(.switch)
                Spacer()
                Button("Peep.Refresh") {
                    Task { await preview.refresh(from: viewModel, maxPixelSize: maxPixelSize) }
                }
                .disabled(preview.isReading)
                if preview.isReading { ProgressView().controlSize(.small) }
            }
            if let frame = preview.frame {
                Image(nsImage: frame.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack {
                    Text("Peep.ReadAt")
                    Text(frame.readAt, style: .time)
                    Text(LocalizedStringKey(frame.requestedCapture ? "Peep.CaptureRequested" : "Peep.CachedFrame"))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                ContentUnavailableView("Peep.Waiting", systemImage: "eye", description: Text("Peep.ConnectionHint"))
            }
            if let error = preview.error {
                Text(error).foregroundStyle(.orange).accessibilityIdentifier("peepError")
            }
            Text("Peep.TimestampHint")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 360, minHeight: 280)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { displaySize = proxy.size }
                    .onChange(of: proxy.size) { displaySize = proxy.size }
            }
        )
        .task {
            if preview.frame == nil { await preview.refresh(from: viewModel, maxPixelSize: maxPixelSize) }
        }
        .task(id: automatic) {
            guard automatic else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(preview.error == nil ? 1 : 5)) } catch { return }
                guard !Task.isCancelled else { return }
                await preview.refresh(from: viewModel, maxPixelSize: maxPixelSize)
            }
        }
        .onChange(of: preview.frame?.readAt) {
            if preview.frame != nil {
                NotificationCenter.default.post(name: .MAAPreviewFrameDisplayed, object: nil)
            }
        }
        .onDisappear { preview.cancel() }
    }
}
