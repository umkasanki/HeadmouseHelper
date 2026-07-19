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

    func apply(_ movement: MovementSettings, to device: HidDevice) {
        guard let systemClient,
              let services = IOHIDEventSystemClientCopyServices(systemClient) as? [IOHIDServiceClient]
        else { return }

        for service in services where matches(service, device) {
            // Resolution (speed). Re-poke acceleration afterwards so it applies.
            setFixed(service, kIOHIDPointerResolutionKey, movement.pointerResolution)
            let type = accelerationType(service)
            setFixed(service, type, movement.disableAcceleration ? -1 : movement.acceleration)
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
}
