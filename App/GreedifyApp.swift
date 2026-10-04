import GreedifyKit
import SwiftUI

@main
struct GreedifyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            Themed { PopoverView() }
                .environment(model)
        } label: {
            MenuBarItem()
                .environment(model)
        }
        .menuBarExtraStyle(.window)

        Window("Set up Greedify", id: WindowID.setup) {
            SetupView()
                .environment(model)
                .modifier(DockWhileOpen())
        }
        .windowResizability(.contentSize)
        .handlesExternalEvents(matching: ["greedify://callback"])

        Settings {
            SettingsView()
                .environment(model)
        }
        .commands { GreedifyCommands(model: model) }
    }
}

enum WindowID {
    static let setup = "setup" // the main window is AppKit-owned: see MainWindowController
}

/// Shows the Dock icon only while a window is open (spec §4.9).
struct DockWhileOpen: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate()
            }
            .onDisappear {
                // Stay a regular app if another Greedify window is still open.
                let others = NSApp.windows.filter { $0.isVisible && $0.canBecomeMain }
                if others.count <= 1 { NSApp.setActivationPolicy(.accessory) }
            }
    }
}

struct GreedifyCommands: Commands {
    let model: AppModel
    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Toggle Lyrics") { model.showLyrics.toggle() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
        }
    }
}
