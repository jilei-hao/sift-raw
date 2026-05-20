import Foundation

enum PhotoScanner {
    static let rawExtensions: Set<String> = ["arw"]
    static let jpegExtensions: Set<String> = ["jpg", "jpeg"]

    static func scan(folder: URL, recursive: Bool = false) throws -> [PhotoGroup] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
        var files: [URL] = []

        if recursive {
            guard let enumerator = fm.enumerator(
                at: folder,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { return [] }
            for case let url as URL in enumerator {
                let values = try url.resourceValues(forKeys: Set(keys))
                if values.isRegularFile == true {
                    files.append(url)
                }
            }
        } else {
            let entries = try fm.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )
            for url in entries {
                let values = try url.resourceValues(forKeys: Set(keys))
                if values.isRegularFile == true {
                    files.append(url)
                }
            }
        }

        var groups: [String: PhotoGroup] = [:]

        for url in files {
            let ext = url.pathExtension.lowercased()
            let isRaw = rawExtensions.contains(ext)
            let isJpeg = jpegExtensions.contains(ext)
            guard isRaw || isJpeg else { continue }

            let basename = url.deletingPathExtension().lastPathComponent
            let key = basename.lowercased()

            var group = groups[key] ?? PhotoGroup(id: basename)
            if isRaw {
                group.raw = url
            } else {
                group.jpeg = url
            }
            groups[key] = group
        }

        return groups.values.sorted { lhs, rhs in
            lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }
}
