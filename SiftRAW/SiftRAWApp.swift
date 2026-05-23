import SwiftUI

@main
struct SiftRAWApp: App {
    @StateObject private var session = CullSession()

    var body: some Scene {
        WindowGroup("SiftRAW") {
            ContentView()
                .environmentObject(session)
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .newItem) {
                Button("Open Source Folder…") {
                    NotificationCenter.default.post(name: .pickSourceFolder, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Choose Destination Folder…") {
                    NotificationCenter.default.post(name: .pickDestinationFolder, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command])

                Divider()

                Button("Reset All Decisions") {
                    NotificationCenter.default.post(name: .resetAllDecisions, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Apply Decisions") {
                    NotificationCenter.default.post(name: .applyDecisions, object: nil)
                }
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }

        Settings {
            PreferencesView()
        }
    }
}

extension Notification.Name {
    static let pickSourceFolder = Notification.Name("pickSourceFolder")
    static let pickDestinationFolder = Notification.Name("pickDestinationFolder")
    static let resetAllDecisions = Notification.Name("resetAllDecisions")
    static let applyDecisions = Notification.Name("applyDecisions")
}
