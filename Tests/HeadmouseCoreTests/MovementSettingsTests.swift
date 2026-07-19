import XCTest
@testable import HeadmouseCore

final class MovementSettingsTests: XCTestCase {
    func testResolutionMapping() {
        // Exponential map: slow=1600 at speed 0, fast=40 at speed 1,
        // geometric mid ≈ 253 at speed 0.5.
        XCTAssertEqual(MovementSettings(speed: 0).pointerResolution, 1600, accuracy: 0.001)
        XCTAssertEqual(MovementSettings(speed: 1).pointerResolution, 40, accuracy: 0.001)
        XCTAssertEqual(MovementSettings(speed: 0.5).pointerResolution, 252.98, accuracy: 0.5)
    }

    func testFasterMeansLowerResolution() {
        XCTAssertLessThan(MovementSettings(speed: 0.9).pointerResolution,
                          MovementSettings(speed: 0.1).pointerResolution)
    }

    func testClamps() {
        XCTAssertEqual(MovementSettings(speed: 2).speed, 1)
        XCTAssertEqual(MovementSettings(speed: -1).speed, 0)
        XCTAssertEqual(MovementSettings(acceleration: 100).acceleration, 40)
    }

    func testCodableRoundTrip() throws {
        let s = MovementSettings(speed: 0.3, acceleration: 12, disableAcceleration: true)
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(MovementSettings.self, from: data), s)
    }

    func testResilientDecodeKeepsKnownKeys() throws {
        let data = #"{"speed": 0.8}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(MovementSettings.self, from: data)
        XCTAssertEqual(s.speed, 0.8, accuracy: 0.001)
        XCTAssertFalse(s.disableAcceleration, "missing key takes the default")
    }
}
