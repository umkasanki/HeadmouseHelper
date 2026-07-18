import XCTest
@testable import HeadmouseCore

/// In-memory seizer for testing the controller without IOKit or hardware.
private final class FakeSeizer: HeadMouseSeizing {
    var onDevicesChanged: (() -> Void)?
    var available: [HidDevice]
    private(set) var seized: Set<String> = []

    init(available: [HidDevice]) { self.available = available }

    func connectedDevices() -> [HidDevice] { available }
    func seize(_ device: HidDevice) -> Bool { seized.insert(device.id); return true }
    func release(_ device: HidDevice) { seized.remove(device.id) }
    func releaseAll() { seized.removeAll() }

    /// Simulate a hotplug event.
    func changeDevices(to devices: [HidDevice]) {
        available = devices
        onDevicesChanged?()
    }
}

final class TrackingControllerTests: XCTestCase {
    private let head = HidDevice(vendorID: 0x0A95, productID: 0x0003, name: "HeadMouse Nano")

    private func makeStore() -> SettingsStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return SettingsStore(directory: dir)
    }

    func testDefaultsToTrackingWhenDevicePresent() {
        let seizer = FakeSeizer(available: [head])
        let c = TrackingController(seizer: seizer, store: makeStore())
        XCTAssertEqual(c.status, .tracking)
        XCTAssertTrue(seizer.seized.isEmpty, "tracking must not seize the device")
    }

    func testNoDeviceWhenNoneConnected() {
        let c = TrackingController(seizer: FakeSeizer(available: []), store: makeStore())
        XCTAssertEqual(c.status, .noDevice)
    }

    func testStopSeizesAndStartReleases() {
        let seizer = FakeSeizer(available: [head])
        let c = TrackingController(seizer: seizer, store: makeStore())

        c.setTracking(false)
        XCTAssertEqual(c.status, .stopped)
        XCTAssertTrue(seizer.seized.contains(head.id), "stopping must seize the device")

        c.setTracking(true)
        XCTAssertEqual(c.status, .tracking)
        XCTAssertFalse(seizer.seized.contains(head.id), "starting must release the device")
    }

    func testStoppedStatePersistsAcrossRestart() {
        let store = makeStore()
        let first = TrackingController(seizer: FakeSeizer(available: [head]), store: store)
        first.setTracking(false)

        // New controller + new seizer, same store → simulates an app restart.
        let seizer = FakeSeizer(available: [head])
        let second = TrackingController(seizer: seizer, store: store)
        XCTAssertEqual(second.status, .stopped)
        XCTAssertTrue(seizer.seized.contains(head.id), "a restart must re-seize a stopped device")
    }

    func testReplugReseizesWhileStopped() {
        let seizer = FakeSeizer(available: [head])
        let c = TrackingController(seizer: seizer, store: makeStore())
        c.setTracking(false)

        // Unplug…
        seizer.changeDevices(to: [])
        XCTAssertEqual(c.status, .noDevice)

        // …and replug: must be seized again automatically.
        seizer.changeDevices(to: [head])
        XCTAssertEqual(c.status, .stopped)
        XCTAssertTrue(seizer.seized.contains(head.id), "a replug while stopped must re-seize")
    }

    func testObserverFiresOnToggle() {
        let c = TrackingController(seizer: FakeSeizer(available: [head]), store: makeStore())
        var count = 0
        c.observe { count += 1 }
        c.toggle()
        XCTAssertGreaterThan(count, 0)
    }
}
