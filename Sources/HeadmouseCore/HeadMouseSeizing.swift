import Foundation

/// Port: exclusive control over head-mouse HID devices.
///
/// The macOS adapter (IOKitSeizer) implements this with `IOHIDManager` and
/// `kIOHIDOptionsTypeSeizeDevice`: while a device is seized, the window server
/// receives none of its pointer reports, so the cursor freezes — that is how we
/// "stop tracking" a device that has no power button, without unplugging it.
///
/// Keeping this as a protocol lets TrackingController be unit-tested on any
/// platform with a fake, away from IOKit and real hardware.
public protocol HeadMouseSeizing: AnyObject {
    /// All currently-connected mouse-like HID devices.
    func connectedDevices() -> [HidDevice]

    /// Seize the device exclusively (= stop tracking / freeze the cursor).
    /// Returns true on success.
    @discardableResult
    func seize(_ device: HidDevice) -> Bool

    /// Release a previously-seized device (= start tracking).
    func release(_ device: HidDevice)

    /// Release everything currently seized.
    func releaseAll()

    /// Invoked when devices are plugged in or removed, so the controller can
    /// re-apply the desired state (e.g. re-seize after a replug).
    var onDevicesChanged: (() -> Void)? { get set }
}
