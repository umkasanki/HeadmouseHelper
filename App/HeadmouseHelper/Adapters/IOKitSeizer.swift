import Foundation
import HeadmouseCore
import IOKit
import IOKit.hid

/// macOS adapter for HeadMouseSeizing, backed by IOKit.
///
/// Crucially, the ONLY thing that ever opens a HID device is the seize itself
/// (exclusive, via `kIOHIDOptionsTypeSeizeDevice`). Enumeration reads the IO
/// registry directly and hotplug uses IOKit service notifications — neither
/// opens the device. An earlier version kept an IOHIDManager open in *shared*
/// mode for enumeration/hotplug; that shared handle stopped the seize from
/// taking exclusive control, so the cursor kept moving while "stopped".
final class IOKitSeizer: HeadMouseSeizing {
    var onDevicesChanged: (() -> Void)?

    private var seized: [String: IOHIDManager] = [:]
    private var notifyPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0

    init() {
        setUpHotplugNotifications()
    }

    // MARK: - HeadMouseSeizing

    func connectedDevices() -> [HidDevice] {
        var result: [HidDevice] = []
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(kIOHIDDeviceKey), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            if registryInt(service, kIOHIDPrimaryUsagePageKey) == kHIDPage_GenericDesktop,
               registryInt(service, kIOHIDPrimaryUsageKey) == kHIDUsage_GD_Mouse,
               let vid = registryInt(service, kIOHIDVendorIDKey),
               let pid = registryInt(service, kIOHIDProductIDKey) {
                let hid = HidDevice(
                    vendorID: vid,
                    productID: pid,
                    name: registryString(service, kIOHIDProductKey) ?? "Unknown device",
                    manufacturer: registryString(service, kIOHIDManufacturerKey) ?? ""
                )
                if !result.contains(where: { $0.id == hid.id }) {
                    result.append(hid)
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return result.sorted { $0.name < $1.name }
    }

    @discardableResult
    func seize(_ device: HidDevice) -> Bool {
        if seized[device.id] != nil { return true }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: device.vendorID,
            kIOHIDProductIDKey: device.productID,
        ] as CFDictionary)
        // Drain incoming reports so the seized device's queue doesn't back up.
        let drain: IOHIDValueCallback = { _, _, _, _ in }
        IOHIDManagerRegisterInputValueCallback(manager, drain, nil)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        guard result == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            // kIOReturnNotPermitted (0xE00002E2) here means Input Monitoring
            // hasn't been granted to the app yet.
            NSLog("HeadmouseHelper: seize failed for \(device.name): 0x\(String(result, radix: 16))")
            return false
        }
        seized[device.id] = manager
        return true
    }

    func release(_ device: HidDevice) {
        guard let manager = seized.removeValue(forKey: device.id) else { return }
        close(manager)
    }

    func releaseAll() {
        for (_, manager) in seized { close(manager) }
        seized.removeAll()
    }

    // MARK: - Hotplug (IOKit service notifications — no device is opened)

    private func setUpHotplugNotifications() {
        notifyPort = IONotificationPortCreate(kIOMainPortDefault)
        if let source = IONotificationPortGetRunLoopSource(notifyPort)?.takeUnretainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOServiceMatchingCallback = { context, iterator in
            // Draining the iterator is required to re-arm the notification.
            var obj = IOIteratorNext(iterator)
            while obj != 0 { IOObjectRelease(obj); obj = IOIteratorNext(iterator) }
            guard let context else { return }
            let me = Unmanaged<IOKitSeizer>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { me.onDevicesChanged?() }
        }
        IOServiceAddMatchingNotification(notifyPort, kIOMatchedNotification,
                                         IOServiceMatching(kIOHIDDeviceKey), callback, ctx, &addedIterator)
        drain(addedIterator)
        IOServiceAddMatchingNotification(notifyPort, kIOTerminatedNotification,
                                         IOServiceMatching(kIOHIDDeviceKey), callback, ctx, &removedIterator)
        drain(removedIterator)
    }

    private func drain(_ iterator: io_iterator_t) {
        var obj = IOIteratorNext(iterator)
        while obj != 0 { IOObjectRelease(obj); obj = IOIteratorNext(iterator) }
    }

    // MARK: - Helpers

    private func close(_ manager: IOHIDManager) {
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    }

    private func registryInt(_ service: io_registry_entry_t, _ key: String) -> Int? {
        guard let cf = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() else { return nil }
        return (cf as? NSNumber)?.intValue
    }

    private func registryString(_ service: io_registry_entry_t, _ key: String) -> String? {
        guard let cf = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() else { return nil }
        return cf as? String
    }
}
