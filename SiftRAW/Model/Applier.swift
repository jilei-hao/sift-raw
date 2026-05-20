import Foundation

enum CullMode: String, CaseIterable, Identifiable {
    case move
    case copy
    var id: String { rawValue }
    var label: String { self == .move ? "Move" : "Copy" }
}

struct ApplyPlan {
    struct Op {
        let groupID: String
        let source: URL
        let destination: URL
    }
    let ops: [Op]
    let appliedGroupIDs: Set<String>
}

enum ApplierError: LocalizedError {
    case destinationMissing
    case fileOperationFailed(URL, URL, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .destinationMissing:
            return "No destination folder is chosen."
        case .fileOperationFailed(let src, let dst, let underlying):
            return "Failed to process \(src.lastPathComponent) → \(dst.path): \(underlying.localizedDescription)"
        }
    }
}

enum Applier {
    static func buildPlan(
        groups: [PhotoGroup],
        destination: URL,
        splitByType: Bool
    ) -> ApplyPlan {
        let keepDir = destination.appendingPathComponent("keep", isDirectory: true)
        let rejectDir = destination.appendingPathComponent("reject", isDirectory: true)

        var taken: Set<String> = []
        var ops: [ApplyPlan.Op] = []
        var applied: Set<String> = []

        for group in groups {
            let baseDir: URL
            switch group.decision {
            case .keep: baseDir = keepDir
            case .reject: baseDir = rejectDir
            }
            for file in group.allFiles {
                let target = splitByType
                    ? baseDir.appendingPathComponent(typeSubfolder(for: file), isDirectory: true)
                    : baseDir
                let dst = uniqueDestination(in: target, for: file, taken: &taken)
                ops.append(.init(groupID: group.id, source: file, destination: dst))
            }
            applied.insert(group.id)
        }
        return ApplyPlan(ops: ops, appliedGroupIDs: applied)
    }

    private static func typeSubfolder(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if PhotoScanner.rawExtensions.contains(ext) { return "raw" }
        if PhotoScanner.jpegExtensions.contains(ext) { return "jpg" }
        return ext.isEmpty ? "other" : ext
    }

    static func apply(plan: ApplyPlan, mode: CullMode) throws {
        let fm = FileManager.default
        var createdDirs: Set<String> = []
        for op in plan.ops {
            let parent = op.destination.deletingLastPathComponent()
            if !createdDirs.contains(parent.path) {
                try fm.createDirectory(at: parent, withIntermediateDirectories: true)
                createdDirs.insert(parent.path)
            }
            do {
                switch mode {
                case .move:
                    try fm.moveItem(at: op.source, to: op.destination)
                case .copy:
                    try fm.copyItem(at: op.source, to: op.destination)
                }
            } catch {
                throw ApplierError.fileOperationFailed(op.source, op.destination, underlying: error)
            }
        }
    }

    private static func uniqueDestination(
        in directory: URL,
        for source: URL,
        taken: inout Set<String>
    ) -> URL {
        let fm = FileManager.default
        let ext = source.pathExtension
        let stem = source.deletingPathExtension().lastPathComponent
        var candidate = directory.appendingPathComponent(source.lastPathComponent)
        var suffix = 0
        while taken.contains(candidate.path) || fm.fileExists(atPath: candidate.path) {
            suffix += 1
            let newName = ext.isEmpty
                ? "\(stem) (\(suffix))"
                : "\(stem) (\(suffix)).\(ext)"
            candidate = directory.appendingPathComponent(newName)
        }
        taken.insert(candidate.path)
        return candidate
    }
}
