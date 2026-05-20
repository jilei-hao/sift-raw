import SwiftUI
import AppKit

struct ToolbarView: View {
    @EnvironmentObject var session: CullSession

    var body: some View {
        HStack(spacing: 12) {
            folderButton(
                label: "Source",
                url: session.sourceURL,
                action: pickSource
            )
            folderButton(
                label: "Destination",
                url: session.destinationURL,
                action: pickDestination
            )

            Picker("Mode", selection: Binding(
                get: { session.effectiveMode },
                set: { newValue in
                    if session.mode != newValue { session.mode = newValue }
                }
            )) {
                ForEach(CullMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .disabled(session.sourceEqualsDestination)
            .help(session.sourceEqualsDestination
                  ? "Source and destination are the same — Move only."
                  : "Move removes from source. Copy leaves source untouched.")

            Toggle("Split RAW/JPG", isOn: $session.splitByType)
                .toggleStyle(.checkbox)
                .help("When on, RAW files go to raw/ and JPG files go to jpg/ inside each of keep/ and reject/.")

            Spacer()

            countsView

            Button {
                session.apply()
            } label: {
                if session.isApplying {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Apply", systemImage: "tray.and.arrow.down")
                }
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(!session.canApply)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var countsView: some View {
        let counts = session.decisionCounts
        return HStack(spacing: 10) {
            badge("Keep", count: counts.keep, color: .green)
            badge("Reject", count: counts.reject, color: .red)
        }
        .font(.caption.monospacedDigit())
    }

    private func badge(_ title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(title) \(count)")
        }
        .foregroundStyle(.secondary)
    }

    private func folderButton(label: String, url: URL?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(url?.lastPathComponent ?? "Choose…")
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: 200, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .help(url?.path ?? "Pick a folder")
    }

    private func pickSource() {
        if let url = chooseFolder(prompt: "Choose source folder") {
            session.setSource(url)
        }
    }

    private func pickDestination() {
        if let url = chooseFolder(prompt: "Choose destination folder") {
            session.setDestination(url)
        }
    }

    private func chooseFolder(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = prompt
        return panel.runModal() == .OK ? panel.url : nil
    }
}
