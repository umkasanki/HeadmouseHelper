import Foundation

/// Port: applies cursor-movement tuning (speed / acceleration) to a device.
///
/// The macOS adapter (IOKitPointerTuner) sets the device's IOKit pointer
/// properties via IOHIDEventSystemClient. Called while tracking is ON; when the
/// device is seized (stopped) tuning is irrelevant, so it isn't applied.
public protocol PointerTuning: AnyObject {
    func apply(_ movement: MovementSettings, to device: HidDevice)
}
