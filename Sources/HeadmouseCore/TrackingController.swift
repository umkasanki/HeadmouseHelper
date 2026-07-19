import Foundation

/// Coordinates the desired tracking state with the hardware, via the
/// HeadMouseSeizing port. Pure logic — no IOKit, no AppKit — so it is unit
/// tested with a fake seizer.
public final class TrackingController {
    public enum Status: Equatable {
        case tracking  // selected device active, controlling the cursor (green)
        case stopped   // selected device seized / frozen (red)
        case noDevice  // no usable device connected (grey)
    }

    private let seizer: HeadMouseSeizing
    private let store: SettingsStore
    private let tuner: PointerTuning?
    public private(set) var settings: Settings

    private var observers: [() -> Void] = []

    public init(seizer: HeadMouseSeizing, store: SettingsStore, tuner: PointerTuning? = nil) {
        self.seizer = seizer
        self.store = store
        self.tuner = tuner
        self.settings = store.load()
        self.seizer.onDevicesChanged = { [weak self] in self?.apply() }
        apply()
    }

    // MARK: - Observation

    /// Register a UI-refresh block, called whenever status or devices change.
    public func observe(_ block: @escaping () -> Void) {
        observers.append(block)
    }

    private func notify() { observers.forEach { $0() } }

    // MARK: - Queries

    public var devices: [HidDevice] { seizer.connectedDevices() }

    /// The device we currently target: the remembered selection if it is
    /// connected, otherwise the first connected device.
    public var activeDevice: HidDevice? {
        let all = devices
        if let vid = settings.selectedVendorID, let pid = settings.selectedProductID,
           let match = all.first(where: { $0.vendorID == vid && $0.productID == pid }) {
            return match
        }
        return all.first
    }

    public var status: Status {
        guard activeDevice != nil else { return .noDevice }
        return settings.trackingEnabled ? .tracking : .stopped
    }

    // MARK: - Commands

    public func select(_ device: HidDevice) {
        settings.selectedVendorID = device.vendorID
        settings.selectedProductID = device.productID
        store.save(settings)
        apply()
    }

    public func setTracking(_ enabled: Bool) {
        settings.trackingEnabled = enabled
        store.save(settings)
        apply()
    }

    public func toggle() { setTracking(!settings.trackingEnabled) }

    public var movement: MovementSettings { settings.movement }

    public func updateMovement(_ movement: MovementSettings) {
        settings.movement = movement
        store.save(settings)
        apply()
    }

    /// Re-assert movement tuning (e.g. after wake, when macOS resets device props).
    public func reapplyTuning() { apply() }

    public var tremor: TremorSettings { settings.tremor }

    public func updateTremor(_ tremor: TremorSettings) {
        settings.tremor = tremor
        store.save(settings)
        notify()
    }

    // MARK: - Enforcement

    /// Make the hardware match the desired state. Idempotent: release
    /// everything, then seize the active device iff tracking is stopped. Called
    /// on every state change and on device hotplug (so a replug re-seizes).
    private func apply() {
        seizer.releaseAll()
        if let device = activeDevice {
            if settings.trackingEnabled {
                tuner?.apply(settings.movement, to: device)
            } else {
                seizer.seize(device)
            }
        }
        notify()
    }
}
