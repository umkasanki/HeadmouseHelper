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
/// Floats above other windows and stays put when the desktop is clicked.
final class SettingsWindowController {
    private let window: PanelWindow

    init(controller: TrackingController) {
        let hosting = NSHostingController(rootView: SettingsView(model: SettingsModel(controller: controller)))
        window = PanelWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.title = "HeadmouseHelper"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false

        // Stay visible when another app (or the desktop) is clicked. A plain
        // floating window of a background (accessory) app is still pulled off
        // screen on deactivation; canJoinAllSpaces + stationary detaches it from
        // the active-app context so it stays put.
        window.level = .floating
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        // Standard way to show "blocked" secondary buttons: disable them so the
        // system greys them out (a window that can't minimize or zoom).
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
    }

    func toggle(from statusButton: NSStatusBarButton?) {
        if window.isVisible {
            window.close()
            return
        }
        positionBelow(statusButton)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
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
