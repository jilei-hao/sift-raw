import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var session: CullSession
    @State private var showResetConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            ToolbarView()
            Divider()
            PhotoView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            ThumbnailStrip()
        }
        .background(KeyCatcher { event in handleKey(event) })
        .onReceive(NotificationCenter.default.publisher(for: .pickSourceFolder)) { _ in
            pickSource()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pickDestinationFolder)) { _ in
            pickDestination()
        }
        .onReceive(NotificationCenter.default.publisher(for: .resetAllDecisions)) { _ in
            if !session.groups.isEmpty { showResetConfirm = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .applyDecisions)) { _ in
            if session.canApply { session.apply() }
        }
        .alert("Reset all decisions?", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) { session.resetAllDecisions() }
        } message: {
            Text("All photos will be set back to reject. This cannot be undone.")
        }
        .alert(
            "Apply failed",
            isPresented: Binding(
                get: { session.applyError != nil },
                set: { if !$0 { session.applyError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(session.applyError ?? "")
        }
        .alert(
            "Apply complete",
            isPresented: Binding(
                get: { session.lastApplyMessage != nil },
                set: { if !$0 { session.lastApplyMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(session.lastApplyMessage ?? "")
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        if event.modifierFlags.intersection([.command, .option, .control]).isEmpty == false {
            return false
        }
        switch event.keyCode {
        case 124: session.goNext();          return true
        case 123: session.goPrev();          return true
        case 49:  session.toggleCurrentKeep(); return true
        default:  return false
        }
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
        panel.message = prompt
        return panel.runModal() == .OK ? panel.url : nil
    }
}

struct KeyCatcher: NSViewRepresentable {
    let handler: (NSEvent) -> Bool

    func makeNSView(context: Context) -> KeyCatcherView {
        let view = KeyCatcherView()
        view.handler = handler
        return view
    }

    func updateNSView(_ nsView: KeyCatcherView, context: Context) {
        nsView.handler = handler
    }
}

final class KeyCatcherView: NSView {
    var handler: ((NSEvent) -> Bool)?
    private var monitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        installMonitor()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil { removeMonitor() }
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            if self.handler?(event) == true {
                return nil
            }
            return event
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        monitor = nil
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
