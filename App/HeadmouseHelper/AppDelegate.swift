import AppKit
import HeadmouseCore
import IOKit.hid

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var seizer: IOKitSeizer!
    private var controller: TrackingController!
    private var statusBar: StatusBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Seizing a HID device needs Input Monitoring access. Requesting it here
        // registers the app in System Settings › Privacy › Input Monitoring and,
        // the first time, shows the permission prompt.
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }

        seizer = IOKitSeizer()
        controller = TrackingController(seizer: seizer, store: SettingsStore())
        statusBar = StatusBarController(controller: controller)
    }

    // On quit the OS automatically releases any seized device, so the cursor is
    // restored — while the persisted "stopped" preference stays intact, so a
    // relaunch (e.g. after reboot) re-seizes. Nothing to do here.
}
