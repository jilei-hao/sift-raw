import SwiftUI
import AppKit

struct PhotoView: View {
    @EnvironmentObject var session: CullSession
    @State private var image: NSImage?
    @State private var loadingID: String?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.85).ignoresSafeArea(edges: .horizontal)

                if let group = session.currentGroup {
                    content(for: group, size: geo.size)
                } else {
                    emptyState
                }
            }
            .onChange(of: session.currentGroup?.id) { _ in
                loadCurrent(size: geo.size)
            }
            .onChange(of: geo.size) { _ in
                loadCurrent(size: geo.size)
            }
            .onAppear {
                loadCurrent(size: geo.size)
            }
        }
    }

    private func content(for group: PhotoGroup, size: CGSize) -> some View {
        VStack(spacing: 0) {
            ZStack {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                } else {
                    ProgressView()
                        .tint(.white)
                }
                VStack {
                    HStack {
                        decisionBadge(group.decision)
                        Spacer()
                        Text("\(session.currentIndex + 1) / \(session.groups.count)")
                            .font(.callout.monospacedDigit())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.55), in: Capsule())
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    HStack {
                        Text(group.displayName)
                            .font(.callout.monospaced())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.55), in: Capsule())
                            .foregroundStyle(.white)
                        if group.raw != nil && group.jpeg != nil {
                            Text("RAW+JPG")
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.blue.opacity(0.8), in: Capsule())
                                .foregroundStyle(.white)
                        } else if group.raw != nil {
                            Text("RAW")
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.purple.opacity(0.8), in: Capsule())
                                .foregroundStyle(.white)
                        }
                        Spacer()
                    }
                }
                .padding(14)
            }
        }
    }

    private func decisionBadge(_ decision: Decision) -> some View {
        let (text, color): (String, Color) = {
            switch decision {
            case .keep:   return ("KEEP", .green)
            case .reject: return ("REJECT", .red)
            }
        }()
        return Text(text)
            .font(.headline.bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(color.opacity(0.85), in: Capsule())
            .foregroundStyle(.white)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 56))
                .foregroundStyle(.white.opacity(0.5))
            if session.sourceURL == nil {
                Text("Pick a source folder to begin (⌘O).")
                    .foregroundStyle(.white.opacity(0.8))
            } else if let err = session.scanError {
                Text("Scan failed: \(err)")
                    .foregroundStyle(.red)
            } else {
                Text("No .ARW or .JPG files found in this folder.")
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    private func loadCurrent(size: CGSize) {
        guard let group = session.currentGroup else {
            image = nil
            return
        }
        let token = group.id
        loadingID = token
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let target = max(size.width, size.height) * scale

        Task {
            let img = await PreviewLoader.shared.load(url: group.previewURL, maxPixelSize: target)
            await MainActor.run {
                if loadingID == token {
                    image = img
                }
            }
            await prefetchNeighbors(target: target)
        }
    }

    private func prefetchNeighbors(target: CGFloat) async {
        let groups = session.groups
        let idx = session.currentIndex
        let neighbors = [idx + 1, idx - 1].filter { groups.indices.contains($0) }
        for n in neighbors {
            await PreviewLoader.shared.prefetch(url: groups[n].previewURL, maxPixelSize: target)
        }
    }
}
