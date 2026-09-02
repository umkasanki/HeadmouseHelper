import Foundation
import HeadmouseCore
import IOKit
import IOKit.hid

/// macOS adapter for PointerTuning. Sets the device's IOKit pointer properties
/// (resolution = speed, acceleration) via the private IOHIDEventSystemClient API,
/// the way LinearMouse does. Applied while tracking is ON.
///
/// macOS resets these on replug/wake, so `TrackingController` re-applies on
/// hotplug and the app re-applies on wake.
final class IOKitPointerTuner: PointerTuning {
    private let systemClient: IOHIDEventSystemClient?

    init() {
        systemClient = IOHIDEventSystemClientCreate(kCFAllocatorDefault)
    }

    /// macOS Sonoma+ property that reinterprets the acceleration value as a linear
    /// gain. We deliberately do **not** use it — see `apply` — but we do clear it,
    /// in case an earlier build (or another tool) left it raised.
    private let linearScalingKey = "HIDUseLinearScalingMouseAcceleration"

    func apply(_ movement: MovementSettings, to device: HidDevice) {
        guard let systemClient,
              let services = IOHIDEventSystemClientCopyServices(systemClient) as? [IOHIDServiceClient]
        else { return }

        for service in services where matches(service, device) {
            // Speed.
            setFixed(service, kIOHIDPointerResolutionKey, movement.pointerResolution)

            let type = accelerationType(service)
            let supportsLinearScaling = IOHIDServiceClientCopyProperty(service, linearScalingKey as CFString) != nil

            // Acceleration amount (also re-pokes so the resolution change applies).
            // Disabling means writing **zero** — the value LinearMouse writes, and
            // the only variant measured to leave pointer speed intact.
            //
            // The Sonoma+ `HIDUseLinearScalingMouseAcceleration` flag looks like the
            // official way to do this and was used here at first, paired with a
            // "neutral" 0.6875 acceleration. On device that combination costs about
            // eight times the pointer speed: the cursor reported a resolution of 49
            // yet moved like the system default of 400. It went unnoticed because the
            // original check was by feel over a remote desktop with nothing to compare
            // against; LinearMouse driving the same device gave us that comparison.
            setFixed(service, type, movement.disableAcceleration ? 0 : movement.acceleration)

            // Clear the flag rather than set it, so a value left raised by an earlier
            // build (or another tool) cannot silently reinterpret what we just wrote.
            if supportsLinearScaling {
                setInt(service, linearScalingKey, 0)
            }
        }
    }

    // MARK: - Helpers

    private func matches(_ service: IOHIDServiceClient, _ device: HidDevice) -> Bool {
        intProp(service, kIOHIDVendorIDKey) == device.vendorID
            && intProp(service, kIOHIDProductIDKey) == device.productID
    }

    /// Which property key holds the acceleration value (LinearMouse's logic).
    private func accelerationType(_ service: IOHIDServiceClient) -> String {
        if let type = IOHIDServiceClientCopyProperty(service, kIOHIDPointerAccelerationTypeKey as CFString) as? String {
            return type
        }
        if IOHIDServiceClientCopyProperty(service, kIOHIDPointerAccelerationKey as CFString) != nil {
            return kIOHIDPointerAccelerationKey
        }
        return kIOHIDMouseAccelerationTypeKey
    }

    private func intProp(_ service: IOHIDServiceClient, _ key: String) -> Int? {
        (IOHIDServiceClientCopyProperty(service, key as CFString) as? NSNumber)?.intValue
    }

    @discardableResult
    private func setFixed(_ service: IOHIDServiceClient, _ key: String, _ value: Double) -> Bool {
        IOHIDServiceClientSetProperty(service, key as CFString, NSNumber(value: Int32(value * 65_536)))
    }

    @discardableResult
    private func setInt(_ service: IOHIDServiceClient, _ key: String, _ value: Int) -> Bool {
        IOHIDServiceClientSetProperty(service, key as CFString, NSNumber(value: value))
    }
}
