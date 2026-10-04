import AppKit
import ApplicationServices

public enum MediaKeyAction: Equatable, Sendable { case playPause, next, previous }

public enum MediaKeyDecoder {
    /// Decodes an `NSEvent.systemDefined` media-key event (subtype 8).
    /// `data1` = keyCode << 16 | keyState << 8 | repeat; keyState 0x0A = down, 0x0B = up.
    public static func decode(subtype: Int16, data1: Int) -> (action: MediaKeyAction, isDown: Bool)? {
        guard subtype == 8 else { return nil }
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let keyState = (data1 & 0xFF00) >> 8
        let action: MediaKeyAction
        switch keyCode {
        case 16: action = .playPause          // NX_KEYTYPE_PLAY
        case 17, 19: action = .next           // NX_KEYTYPE_NEXT, NX_KEYTYPE_FAST
        case 18, 20: action = .previous       // NX_KEYTYPE_PREVIOUS, NX_KEYTYPE_REWIND
        default: return nil
        }
        return (action, keyState == 0x0A)
    }
}

/// Global event tap that turns media keys into Greedify actions and swallows them,
/// so macOS never forwards them to Apple Music. Needs Accessibility permission.
@MainActor
public final class MediaKeyTap {
    public var onAction: (MediaKeyAction) -> Void
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    public init(onAction: @escaping (MediaKeyAction) -> Void) { self.onAction = onAction }

    public static var hasPermission: Bool { AXIsProcessTrusted() }

    public static func requestPermission() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    public var isRunning: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    /// Returns false if the tap couldn't be created (usually: no Accessibility permission).
    @discardableResult
    public func start() -> Bool {
        guard tap == nil else { return true }
        let mask = CGEventMask(1 << 14) // NX_SYSDEFINED
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<MediaKeyTap>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                MainActor.assumeIsolated { me.reenable() }
                return Unmanaged.passUnretained(event)
            }
            guard let decoded = MediaKeyTap.decode(event) else { return Unmanaged.passUnretained(event) }
            if decoded.isDown {
                let action = decoded.action
                MainActor.assumeIsolated { me.onAction(action) }
            }
            return nil // swallow both key-down and key-up
        }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: callback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        tap = port
        source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    public func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
    }

    private func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    nonisolated static func decode(_ event: CGEvent) -> (action: MediaKeyAction, isDown: Bool)? {
        guard let ns = NSEvent(cgEvent: event), ns.type == .systemDefined else { return nil }
        return MediaKeyDecoder.decode(subtype: ns.subtype.rawValue, data1: ns.data1)
    }
}

/// Quits Apple Music whenever it launches (catches AirPods/headphone buttons the tap can't see).
@MainActor
public final class MusicBlocker {
    public nonisolated static let musicBundleID = "com.apple.Music"
    public var isEnabled: Bool
    private var observer: NSObjectProtocol?

    public init(isEnabled: Bool) { self.isEnabled = isEnabled }

    public nonisolated static func shouldBlock(bundleID: String?, enabled: Bool) -> Bool {
        enabled && bundleID == musicBundleID
    }

    public func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let self, let app, Self.shouldBlock(bundleID: app.bundleIdentifier, enabled: self.isEnabled) else { return }
                if !app.terminate() { app.forceTerminate() }
            }
        }
    }

    public func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
    }
}

/// What a double-click on a window's title bar should do, from the system setting
/// (System Settings → Desktop & Dock → "Double-click a window's title bar to").
public enum TitleBarDoubleClick: Equatable, Sendable {
    case zoom, minimize, none

    /// `setting` is the global `AppleActionOnDoubleClick` default; unset means the macOS default, zoom.
    public static func action(for setting: String?) -> TitleBarDoubleClick {
        switch setting?.lowercased() {
        case "minimize": .minimize
        case "none": .none
        default: .zoom // "Maximize", "Fill" or unset
        }
    }

    public static var current: TitleBarDoubleClick {
        action(for: UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleActionOnDoubleClick"] as? String)
    }
}
