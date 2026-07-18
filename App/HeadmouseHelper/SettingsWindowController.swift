import AppKit
import HeadmouseCore
import SwiftUI

/// A window that cannot be dragged off-screen: its frame is always constrained
/// to the current screen's visible area (below the menu bar, above the Dock).
private final class PanelWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        let bounds = (screen ?? self.screen ?? NSScreen.main)?.visibleFrame
        guard let visible = bounds else { return frameRect }
        var r = frameRect
        r.origin.x = min(max(r.origin.x, visible.minX), visible.maxX - r.width)
        r.origin.y = min(max(r.origin.y, visible.minY), visible.maxY - r.height)
        return r
    }
}

/// A standard titled window (with the real system traffic lights) hosting the
/// control UI. Minimize and zoom are natively disabled — only close is active.
/// Auto-closes when the user clicks outside it (like a popover).
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let window: PanelWindow

    init(controller: TrackingController) {
        let hosting = NSHostingController(rootView: SettingsView(model: SettingsModel(controller: controller)))
        window = PanelWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.contentViewController = hosting
        window.title = "HeadmouseHelper"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = self

        // Standard way to show "blocked" secondary buttons: disable them so the
        // system greys them out (a window that can't minimize or zoom).
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
    }

    func show(from statusButton: NSStatusBarButton?) {
        positionBelow(statusButton)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Auto-close when the user clicks outside the window (it lost key focus).
    func windowDidResignKey(_ notification: Notification) {
        window.close()
    }

    private func positionBelow(_ statusButton: NSStatusBarButton?) {
        guard let anchor = statusButton?.window?.frame else {
            window.center()
            return
        }
        let size = window.frame.size
        let x = anchor.midX - size.width / 2
        let y = anchor.minY - size.height - 2
        // setFrame runs the origin through constrainFrameRect, so it lands
        // on-screen even if the status item sits near a corner.
        window.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: false)
    }
}
