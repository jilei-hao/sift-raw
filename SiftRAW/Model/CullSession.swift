import Foundation
import SwiftUI

@MainActor
final class CullSession: ObservableObject {
    @Published var sourceURL: URL?
    @Published var destinationURL: URL?
    @Published var mode: CullMode = .copy
    @Published var splitByType: Bool = true
    @Published private(set) var groups: [PhotoGroup] = []
    @Published var currentIndex: Int = 0
    @Published var scanError: String?
    @Published var applyError: String?
    @Published var isApplying: Bool = false
    @Published var lastApplyMessage: String?

    var currentGroup: PhotoGroup? {
        guard groups.indices.contains(currentIndex) else { return nil }
        return groups[currentIndex]
    }

    var hasKeeps: Bool {
        groups.contains { $0.decision == .keep }
    }

    var decisionCounts: (keep: Int, reject: Int) {
        var k = 0, r = 0
        for g in groups {
            switch g.decision {
            case .keep: k += 1
            case .reject: r += 1
            }
        }
        return (k, r)
    }

    var effectiveMode: CullMode {
        if let s = sourceURL, let d = destinationURL, s.standardizedFileURL == d.standardizedFileURL {
            return .move
        }
        return mode
    }

    var sourceEqualsDestination: Bool {
        guard let s = sourceURL, let d = destinationURL else { return false }
        return s.standardizedFileURL == d.standardizedFileURL
    }

    func setSource(_ url: URL) {
        sourceURL = url
        scanError = nil
        rescan()
    }

    func setDestination(_ url: URL) {
        destinationURL = url
    }

    func rescan() {
        guard let folder = sourceURL else {
            groups = []
            currentIndex = 0
            return
        }
        do {
            let scanned = try PhotoScanner.scan(folder: folder)
            groups = scanned
            currentIndex = scanned.isEmpty ? 0 : 0
            scanError = nil
        } catch {
            groups = []
            currentIndex = 0
            scanError = error.localizedDescription
        }
    }

    func goNext() {
        guard !groups.isEmpty else { return }
        currentIndex = min(currentIndex + 1, groups.count - 1)
    }

    func goPrev() {
        guard !groups.isEmpty else { return }
        currentIndex = max(currentIndex - 1, 0)
    }

    func jump(to index: Int) {
        guard groups.indices.contains(index) else { return }
        currentIndex = index
    }

    func toggleCurrentKeep() {
        guard groups.indices.contains(currentIndex) else { return }
        groups[currentIndex].decision = groups[currentIndex].decision == .keep ? .reject : .keep
    }

    func resetAllDecisions() {
        for i in groups.indices {
            groups[i].decision = .reject
        }
    }

    var canApply: Bool {
        destinationURL != nil && hasKeeps && !isApplying
    }

    func apply() {
        guard let destination = destinationURL else {
            applyError = ApplierError.destinationMissing.localizedDescription
            return
        }
        isApplying = true
        applyError = nil
        lastApplyMessage = nil

        let plan = Applier.buildPlan(groups: groups, destination: destination, splitByType: splitByType)
        let appliedMode = effectiveMode
        let appliedIDs = plan.appliedGroupIDs

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try Applier.apply(plan: plan, mode: appliedMode)
                await MainActor.run {
                    guard let self else { return }
                    self.groups.removeAll { appliedIDs.contains($0.id) }
                    if self.currentIndex >= self.groups.count {
                        self.currentIndex = max(0, self.groups.count - 1)
                    }
                    self.isApplying = false
                    self.lastApplyMessage = "Applied \(appliedIDs.count) photo\(appliedIDs.count == 1 ? "" : "s")."
                }
            } catch {
                await MainActor.run {
                    self?.isApplying = false
                    self?.applyError = error.localizedDescription
                }
            }
        }
    }
}
