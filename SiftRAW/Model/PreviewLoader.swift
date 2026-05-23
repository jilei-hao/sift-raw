import AppKit
import ImageIO
import Foundation

actor PreviewLoader {
    static let shared = PreviewLoader()

    struct Request {
        let url: URL
        let maxPixelSize: CGFloat
    }

    private struct CacheKey: Hashable {
        let path: String
        let pixelSize: Int

        init(path: String, pixelSize: Int) {
            self.path = path
            self.pixelSize = pixelSize
        }

        init(url: URL, maxPixelSize: CGFloat) {
            self.path = url.path
            self.pixelSize = Int(max(1, maxPixelSize.rounded()))
        }
    }

    private var cache: [CacheKey: NSImage] = [:]
    private var lru: [CacheKey] = []
    private var inFlight: [CacheKey: Task<NSImage?, Never>] = [:]
    private var windowKeys: Set<CacheKey> = []
    private let capacity: Int

    // Capacity sized for the largest configurable big-preview window (±20 =
    // 41 entries) plus the visible thumbnails in ThumbnailStrip, with headroom.
    init(capacity: Int = 80) {
        self.capacity = capacity
    }

    func load(url: URL, maxPixelSize: CGFloat) async -> NSImage? {
        let key = CacheKey(url: url, maxPixelSize: maxPixelSize)
        if let cached = cache[key] {
            touch(key)
            return cached
        }
        if let existing = inFlight[key] {
            return await existing.value
        }
        return await beginDecode(key: key, url: url, priority: .userInitiated).value
    }

    /// Declares the set of previews that should be kept warm, closest-first.
    /// Cancels previously-windowed prefetches that fell out of the new window,
    /// and schedules any newly-desired entries that aren't already cached or
    /// in flight. Loads issued via `load(...)` are not managed by the window
    /// and never get cancelled here.
    func setActiveWindow(_ requests: [Request]) {
        let desired = requests.map { CacheKey(url: $0.url, maxPixelSize: $0.maxPixelSize) }
        let desiredSet = Set(desired)

        for key in windowKeys where !desiredSet.contains(key) {
            inFlight[key]?.cancel()
            inFlight[key] = nil
        }
        windowKeys = desiredSet

        for (i, key) in desired.enumerated() {
            if cache[key] != nil {
                touch(key)
                continue
            }
            if inFlight[key] != nil { continue }
            _ = beginDecode(key: key, url: requests[i].url, priority: .utility)
        }
    }

    @discardableResult
    private func beginDecode(
        key: CacheKey,
        url: URL,
        priority: TaskPriority
    ) -> Task<NSImage?, Never> {
        let pixelSize = key.pixelSize
        let task = Task<NSImage?, Never>.detached(priority: priority) { [weak self] in
            if Task.isCancelled {
                await self?.clearInFlight(key: key)
                return nil
            }
            let image = PreviewLoader.decode(url: url, maxPixelSize: pixelSize)
            if Task.isCancelled || image == nil {
                await self?.clearInFlight(key: key)
                return nil
            }
            await self?.finishDecode(key: key, image: image!)
            return image
        }
        inFlight[key] = task
        return task
    }

    private func finishDecode(key: CacheKey, image: NSImage) {
        inFlight[key] = nil
        store(key: key, image: image)
    }

    private func clearInFlight(key: CacheKey) {
        inFlight[key] = nil
    }

    private func touch(_ key: CacheKey) {
        if let idx = lru.firstIndex(of: key) {
            lru.remove(at: idx)
        }
        lru.append(key)
    }

    private func store(key: CacheKey, image: NSImage) {
        cache[key] = image
        touch(key)
        while lru.count > capacity {
            let evict = lru.removeFirst()
            cache.removeValue(forKey: evict)
        }
    }

    private static func decode(url: URL, maxPixelSize: Int) -> NSImage? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let src = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
            return nil
        }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOptions as CFDictionary) else {
            return nil
        }
        let size = NSSize(width: cg.width, height: cg.height)
        return NSImage(cgImage: cg, size: size)
    }
}
