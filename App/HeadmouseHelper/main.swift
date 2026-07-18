import AppKit

// Menu-bar / accessory app: no Dock icon, no main window (see LSUIElement).
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
