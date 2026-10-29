import SwiftUI

struct PeepView: View {
    @EnvironmentObject private var viewModel: MAAViewModel
    @StateObject private var preview = PeepViewModel()
    @State private var automatic = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Toggle("Peep.Automatic", isOn: $automatic)
                    .toggleStyle(.switch)
                Spacer()
                Button("Peep.Refresh") {
                    Task { await preview.refresh(from: viewModel) }
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
        .task(id: automatic) {
            if preview.frame == nil { await preview.refresh(from: viewModel) }
            while automatic && !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(preview.error == nil ? 1 : 5)) } catch { return }
                guard !Task.isCancelled else { return }
                await preview.refresh(from: viewModel)
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
