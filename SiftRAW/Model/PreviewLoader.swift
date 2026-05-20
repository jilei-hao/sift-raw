import AppKit
import ImageIO
import Foundation

actor PreviewLoader {
    static let shared = PreviewLoader()

    private struct CacheKey: Hashable {
        let path: String
        let pixelSize: Int
    }

    private var cache: [CacheKey: NSImage] = [:]
    private var lru: [CacheKey] = []
    private let capacity: Int

    init(capacity: Int = 8) {
        self.capacity = capacity
    }

    func load(url: URL, maxPixelSize: CGFloat) async -> NSImage? {
        let pixelSize = Int(max(1, maxPixelSize.rounded()))
        let key = CacheKey(path: url.path, pixelSize: pixelSize)
        if let cached = cache[key] {
            touch(key)
            return cached
        }

        let image = await Task.detached(priority: .userInitiated) {
            PreviewLoader.decode(url: url, maxPixelSize: pixelSize)
        }.value

        if let image {
            store(key: key, image: image)
        }
        return image
    }

    func prefetch(url: URL, maxPixelSize: CGFloat) {
        let pixelSize = Int(max(1, maxPixelSize.rounded()))
        let key = CacheKey(path: url.path, pixelSize: pixelSize)
        if cache[key] != nil { return }
        Task.detached(priority: .utility) { [weak self] in
            guard let image = PreviewLoader.decode(url: url, maxPixelSize: pixelSize) else { return }
            await self?.store(key: key, image: image)
        }
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
