import AppKit
import SwiftUI

extension View {
    /// Hover text, drawn by Greedify itself: SwiftUI's `.help` tooltips never appeared in the main window or the
    /// popover. VoiceOver reads the text as the element's hint.
    func hoverHelp(_ text: String) -> some View { modifier(HoverHelp(text: text)) }
}

private struct HoverHelp: ViewModifier {
    let text: String
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .accessibilityHint(Text(text))
            .onHover { inside in
                if inside, !text.isEmpty { HoverTip.shared.schedule(text, owner: id) } else { HoverTip.shared.cancel(owner: id) }
            }
            .onDisappear { HoverTip.shared.cancel(owner: id) }
    }
}

/// One small borderless window, reused for every hover text. Being a window, it floats above the popover and isn't
/// covered by neighbouring views or cut off at the popover's edge.
@MainActor
final class HoverTip {
    static let shared = HoverTip()

    private var panel: NSPanel?
    private var label: NSTextField?
    private var pending: Task<Void, Never>?
    private var owner: UUID?
    private var monitor: Any?

    func schedule(_ text: String, owner: UUID) {
        pending?.cancel()
        self.owner = owner
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.show(text)
        }
    }

    /// Hides the text, if it's this element's.
    func cancel(owner: UUID) {
        guard self.owner == owner else { return }
        hide()
    }

    func hide() {
        pending?.cancel()
        pending = nil
        owner = nil
        panel?.orderOut(nil)
    }

    private func show(_ text: String) {
        let panel = panel ?? makePanel()
        label?.stringValue = text
        label?.sizeToFit()
        let size = NSSize(width: (label?.frame.width ?? 0) + 14, height: (label?.frame.height ?? 0) + 8)
        // Below and right of the pointer, like the system's tooltips, kept on the pointer's screen.
        let mouse = NSEvent.mouseLocation
        var origin = NSPoint(x: mouse.x + 2, y: mouse.y - 22 - size.height)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })?.visibleFrame {
            origin.x = min(max(origin.x, screen.minX + 4), screen.maxX - size.width - 4)
            if origin.y < screen.minY + 4 { origin.y = mouse.y + 18 } // no room below: above the pointer
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .popUpMenu // above the menu-bar popover
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let background = NSVisualEffectView()
        background.material = .toolTip
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 5
        background.layer?.masksToBounds = true
        panel.contentView = background

        let label = NSTextField(labelWithString: "")
        label.font = .toolTipsFont(ofSize: 0)
        label.textColor = .labelColor
        label.frame.origin = NSPoint(x: 7, y: 4)
        background.addSubview(label)

        // A click, scroll or key press dismisses it, as with the system's tooltips.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.hide() } // local monitors run on the main thread
            return event
        }
        self.panel = panel
        self.label = label
        return panel
    }
}
