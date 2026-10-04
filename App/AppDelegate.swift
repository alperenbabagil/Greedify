import AppKit

extension Notification.Name {
    /// Posted when the user opens Greedify again while it's already running.
    static let greedifyReopen = Notification.Name("com.alperen.greedify.reopen")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Opening Greedify from Finder, Spotlight or Launchpad while it runs in the menu bar would do nothing
    /// (it has no windows, and the menu-bar icon may be hidden behind the notch), so show a window instead.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NotificationCenter.default.post(name: .greedifyReopen, object: nil) }
        return true
    }

    // AppleScript `player state` and `current track` (see Scripting).
    func application(_ sender: NSApplication, delegateHandlesKey key: String) -> Bool {
        key == "playerState" || key == "currentTrack"
    }

    @MainActor @objc var playerState: NSNumber { Scripting.playerState }
    @MainActor @objc var currentTrack: ScriptTrack? { Scripting.currentTrack }
}
