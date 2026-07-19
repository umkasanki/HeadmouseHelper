import AppKit
import HeadmouseCore
import IOKit.hid

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var seizer: IOKitSeizer!
    private var tuner: IOKitPointerTuner!
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
        tuner = IOKitPointerTuner()
        controller = TrackingController(seizer: seizer, store: SettingsStore(), tuner: tuner)
        statusBar = StatusBarController(controller: controller)

        // macOS resets device pointer properties on wake — re-apply our tuning.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil
        )
    }

    @objc private func didWake() { controller.reapplyTuning() }

    // On quit the OS automatically releases any seized device, so the cursor is
    // restored — while the persisted "stopped" preference stays intact, so a
    // relaunch (e.g. after reboot) re-seizes. Nothing to do here.
}
