import SwiftUI

/// User-facing preferences persisted via `@AppStorage`. Centralized here so
/// the key, default, and allowed range stay in sync across views.
enum UserPrefs {
    static let prefetchRadiusKey = "prefetchRadius"
    static let defaultPrefetchRadius = 10
    static let prefetchRadiusRange: ClosedRange<Int> = 1...20

    static func clampedPrefetchRadius(_ value: Int) -> Int {
        min(max(value, prefetchRadiusRange.lowerBound), prefetchRadiusRange.upperBound)
    }
}

struct PreferencesView: View {
    @AppStorage(UserPrefs.prefetchRadiusKey) private var prefetchRadius: Int = UserPrefs.defaultPrefetchRadius

    var body: some View {
        Form {
            Section {
                Stepper(
                    value: Binding(
                        get: { UserPrefs.clampedPrefetchRadius(prefetchRadius) },
                        set: { prefetchRadius = UserPrefs.clampedPrefetchRadius($0) }
                    ),
                    in: UserPrefs.prefetchRadiusRange
                ) {
                    HStack(spacing: 6) {
                        Text("Preview cache window:")
                        Text("±\(prefetchRadius)")
                            .font(.body.monospacedDigit().bold())
                        Text("(\(2 * prefetchRadius + 1) photos)")
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Higher values keep more neighbors decoded and ready for instant scrolling. Each cached preview uses roughly 10–25 MB of memory.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Preview Cache")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding(.vertical, 4)
    }
}
