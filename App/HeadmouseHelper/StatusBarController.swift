import AppKit
import HeadmouseCore

/// The menu-bar item: a state-coloured icon that opens the control window on
/// click.
final class StatusBarController {
    private let item: NSStatusItem
    private let controller: TrackingController
    private let settingsWindow: SettingsWindowController

    init(controller: TrackingController) {
        self.controller = controller
        self.settingsWindow = SettingsWindowController(controller: controller)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = item.button {
            button.action = #selector(toggleWindow)
            button.target = self
        }

        controller.observe { [weak self] in self?.refreshIcon() }
        refreshIcon()
    }

    @objc private func toggleWindow() {
        settingsWindow.toggle(from: item.button)
    }

    private func refreshIcon() {
        guard let button = item.button else { return }

        let color: NSColor
        switch controller.status {
        case .tracking: color = .systemGreen
        case .stopped: color = .systemRed
        case .noDevice: color = .secondaryLabelColor
        }
        button.image = Self.icon(color: color)
    }

    /// The menu-bar glyph: a filled rounded rectangle with a large centered
    /// circular knockout and two small circular knockouts in the top corners
    /// (see tools/MenuBarIcon.svg). Drawn per-state so it can be colour-tinted.
    private static func icon(color: NSColor, height: CGFloat = 15) -> NSImage {
        let s = height / 100          // design space is a 140×100 rectangle
        let width = 140 * s
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()

        let path = NSBezierPath(
            roundedRect: NSRect(x: 0, y: 0, width: width, height: height),
            xRadius: 16 * s, yRadius: 16 * s
        )
        // Knockouts, in design coords (y from the bottom, so the two small
        // circles sit at the *top* corners).
        func knockout(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
            path.appendOval(in: NSRect(x: (cx - r) * s, y: (cy - r) * s,
                                       width: 2 * r * s, height: 2 * r * s))
        }
        knockout(70, 50, 40)   // big centered circle (80% of height)
        knockout(16, 84, 8)    // top-left
        knockout(124, 84, 8)   // top-right

        path.windingRule = .evenOdd
        color.setFill()
        path.fill()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
