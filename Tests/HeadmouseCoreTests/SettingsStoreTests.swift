import XCTest
@testable import HeadmouseCore

final class SettingsStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testDefaultsWhenNoFile() {
        let store = SettingsStore(directory: dir)
        XCTAssertEqual(store.load(), Settings())
    }

    func testSaveThenLoadRoundTrip() {
        let store = SettingsStore(directory: dir)
        var s = Settings()
        s.trackingEnabled = false
        s.selectedVendorID = 0x0A95
        s.selectedProductID = 0x0003
        XCTAssertTrue(store.save(s))

        let fresh = SettingsStore(directory: dir)
        XCTAssertEqual(fresh.load(), s)
    }

    func testCorruptFileFallsBackToDefaults() throws {
        let fileURL = dir.appendingPathComponent("settings.json")
        try "{ not valid json".data(using: .utf8)!.write(to: fileURL)
        let store = SettingsStore(directory: dir)
        XCTAssertEqual(store.load(), Settings())
    }

    func testResilientDecodeKeepsKnownKeys() throws {
        // A file missing newer keys must still load and keep the value it has.
        let fileURL = dir.appendingPathComponent("settings.json")
        try #"{"trackingEnabled": false}"#.data(using: .utf8)!.write(to: fileURL)
        let loaded = SettingsStore(directory: dir).load()
        XCTAssertFalse(loaded.trackingEnabled)
        XCTAssertTrue(loaded.notifyOnChange, "missing key should take the default")
    }
}
