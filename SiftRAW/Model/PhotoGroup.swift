import Foundation

enum Decision: String, Hashable {
    case reject
    case keep
}

struct PhotoGroup: Identifiable, Hashable {
    let id: String
    var raw: URL?
    var jpeg: URL?
    var decision: Decision = .reject

    var previewURL: URL {
        if let jpeg { return jpeg }
        if let raw { return raw }
        fatalError("PhotoGroup \(id) has neither RAW nor JPEG")
    }

    var allFiles: [URL] { [raw, jpeg].compactMap { $0 } }

    var displayName: String {
        if let raw { return raw.lastPathComponent }
        if let jpeg { return jpeg.lastPathComponent }
        return id
    }
}
