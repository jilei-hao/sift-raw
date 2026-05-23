import SwiftUI
import AppKit

struct PhotoView: View {
    @EnvironmentObject var session: CullSession
    @AppStorage(UserPrefs.prefetchRadiusKey) private var prefetchRadius: Int = UserPrefs.defaultPrefetchRadius
    @State private var image: NSImage?
    @State private var loadingID: String?
    @State private var windowDebounce: Task<Void, Never>?

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
            .onChange(of: prefetchRadius) { _ in
                // Settings changes are an explicit user action — refresh
                // immediately rather than waiting on the scroll debounce so
                // the new radius takes effect right away.
                windowDebounce?.cancel()
                windowDebounce = nil
                let scale = NSScreen.main?.backingScaleFactor ?? 2
                let target = max(geo.size.width, geo.size.height) * scale
                Task { await refreshWindow(target: target) }
            }
            .onAppear {
                loadCurrent(size: geo.size)
            }
            .onDisappear {
                windowDebounce?.cancel()
                windowDebounce = nil
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

    private static let windowDebounceNanos: UInt64 = 750_000_000

    private func loadCurrent(size: CGSize) {
        guard let group = session.currentGroup else {
            image = nil
            windowDebounce?.cancel()
            windowDebounce = nil
            Task { await PreviewLoader.shared.setActiveWindow([]) }
            return
        }
        let token = group.id
        loadingID = token
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let target = max(size.width, size.height) * scale

        // Load the visible photo immediately at high priority. If the previous
        // window had already scheduled this key as a prefetch, this joins that
        // in-flight task and Swift escalates its priority automatically.
        Task {
            let img = await PreviewLoader.shared.load(url: group.previewURL, maxPixelSize: target)
            await MainActor.run {
                if loadingID == token {
                    image = img
                }
            }
        }

        scheduleWindowRefresh(target: target)
    }

    // Debounce the ±10 window so fast scrolling doesn't thrash the cache: each
    // arrow press would otherwise cancel and re-schedule 21 prefetches that
    // never get a chance to finish. The window only slides after the user
    // pauses for `windowDebounceNanos`. In-flight prefetches from the previous
    // window keep running during the wait — anything no longer wanted is
    // cancelled by the next setActiveWindow call.
    private func scheduleWindowRefresh(target: CGFloat) {
        windowDebounce?.cancel()
        windowDebounce = Task {
            try? await Task.sleep(nanoseconds: Self.windowDebounceNanos)
            if Task.isCancelled { return }
            await refreshWindow(target: target)
        }
    }

    private func refreshWindow(target: CGFloat) async {
        let groups = session.groups
        let idx = session.currentIndex
        guard groups.indices.contains(idx) else {
            await PreviewLoader.shared.setActiveWindow([])
            return
        }

        let radius = UserPrefs.clampedPrefetchRadius(prefetchRadius)
        var requests: [PreviewLoader.Request] = []
        requests.append(.init(url: groups[idx].previewURL, maxPixelSize: target))
        if radius > 0 {
            for offset in 1...radius {
                let forward = idx + offset
                if groups.indices.contains(forward) {
                    requests.append(.init(url: groups[forward].previewURL, maxPixelSize: target))
                }
                let backward = idx - offset
                if groups.indices.contains(backward) {
                    requests.append(.init(url: groups[backward].previewURL, maxPixelSize: target))
                }
            }
        }
        await PreviewLoader.shared.setActiveWindow(requests)
    }
}
