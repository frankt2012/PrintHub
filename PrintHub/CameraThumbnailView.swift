import AppKit
import SwiftUI

struct CameraThumbnailView: View {
    let url: URL?

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black)

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                VStack(spacing: 6) {
                    Image(systemName: url == nil ? "camera.fill" : "arrow.clockwise")
                        .foregroundStyle(.white.opacity(0.45))
                    Text(url == nil ? "Camera starting…" : "Updating…")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            VStack {
                HStack {
                    Text("LIVE")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.red.opacity(0.8), in: Capsule())
                    Spacer()
                }
                Spacer()
            }
            .padding(8)
            .opacity(image == nil ? 0 : 1)
        }
        .frame(width: 272, height: 153)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        )
        .help("Live camera snapshot")
        .task(id: url) {
            await loadLoop()
        }
    }

    @MainActor
    private func loadLoop() async {
        guard let url else {
            image = nil
            return
        }

        while !Task.isCancelled {
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let loaded = NSImage(data: data) {
                image = loaded
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
}
