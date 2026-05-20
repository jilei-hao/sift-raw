import SwiftUI
import AppKit

struct ThumbnailStrip: View {
    @EnvironmentObject var session: CullSession

    private let thumbSize: CGFloat = 72

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(session.groups.enumerated()), id: \.element.id) { idx, group in
                        ThumbnailCell(
                            group: group,
                            isCurrent: idx == session.currentIndex,
                            size: thumbSize
                        )
                        .id(group.id)
                        .onTapGesture {
                            session.jump(to: idx)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .frame(height: thumbSize + 16)
            .background(.bar)
            .onChange(of: session.currentIndex) { _ in
                if let current = session.currentGroup {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(current.id, anchor: .center)
                    }
                }
            }
        }
    }
}

private struct ThumbnailCell: View {
    let group: PhotoGroup
    let isCurrent: Bool
    let size: CGFloat

    @State private var image: NSImage?

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.black.opacity(0.2))
            .frame(width: size, height: size)
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipped()
                        .cornerRadius(4)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(group.decision == .keep ? Color.green : Color.clear, lineWidth: 5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isCurrent ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .task(id: group.id) {
                let scale = NSScreen.main?.backingScaleFactor ?? 2
                let img = await PreviewLoader.shared.load(
                    url: group.previewURL,
                    maxPixelSize: size * scale
                )
                image = img
            }
    }
}
