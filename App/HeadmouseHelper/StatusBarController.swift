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
            button.action = #selector(handleClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        controller.observe { [weak self] in self?.refreshIcon() }
        refreshIcon()
    }

    /// Left click toggles tracking; right (or ctrl) click shows the menu.
    @objc private func handleClick() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else if controller.status != .noDevice {
            controller.toggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let toggle = NSMenuItem(
            title: controller.status == .tracking ? "Stop tracking" : "Start tracking",
            action: #selector(menuToggle), keyEquivalent: ""
        )
        toggle.target = self
        toggle.isEnabled = controller.status != .noDevice
        menu.addItem(toggle)

        let settings = NSMenuItem(title: "Settings…", action: #selector(menuSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit HeadmouseHelper", action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        if let button = item.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        }
    }

    @objc private func menuToggle() { controller.toggle() }
    @objc private func menuSettings() { settingsWindow.show(from: item.button) }
    @objc private func menuQuit() { NSApp.terminate(nil) }

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
