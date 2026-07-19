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

    /// macOS Sonoma+ property to disable acceleration while keeping pointer speed
    /// — the same mechanism as System Settings' toggle (as used by LinearMouse).
    private let linearScalingKey = "HIDUseLinearScalingMouseAcceleration"

    /// macOS default acceleration; used as a neutral linear gain when acceleration
    /// is disabled via linear scaling, so Speed alone governs the pointer.
    private static let neutralAcceleration = 0.6875

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
            // With linear scaling ON, the acceleration value acts as a linear gain
            // multiplier — so when disabled we write a neutral value (macOS default),
            // letting Speed alone govern the pointer. On systems without linear
            // scaling, −1 is the disable fallback.
            let acceleration: Double
            if movement.disableAcceleration {
                acceleration = supportsLinearScaling ? Self.neutralAcceleration : -1
            } else {
                acceleration = movement.acceleration
            }
            setFixed(service, type, acceleration)

            // Official disable/enable LAST, so the linear-scaling flag is
            // authoritative (writing an acceleration value after it could
            // otherwise re-enable acceleration).
            if supportsLinearScaling {
                setInt(service, linearScalingKey, movement.disableAcceleration ? 1 : 0)
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
