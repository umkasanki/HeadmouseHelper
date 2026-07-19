import XCTest
@testable import HeadmouseCore

final class TremorFilterTests: XCTestCase {
    func testNoInputProducesNoOutput() {
        let f = TremorFilter()
        let out = f.process(dx: 0, dy: 0, dt: 0.008)
        XCTAssertEqual(out.dx, 0, accuracy: 1e-9)
        XCTAssertEqual(out.dy, 0, accuracy: 1e-9)
    }

    func testJitterWithinDeadzoneIsSuppressed() {
        let f = TremorFilter(smoothing: 1.0, deadzone: 0.5)
        // A tiny movement below the dead zone must produce no cursor movement.
        let out = f.process(dx: 0.2, dy: 0, dt: 0.008)
        XCTAssertEqual(out.dx, 0, accuracy: 1e-9)
        XCTAssertEqual(out.dy, 0, accuracy: 1e-9)
    }

    func testOscillatingJitterStaysNearZero() {
        let f = TremorFilter(smoothing: 1.0, deadzone: 0.5)
        var total = 0.0
        // Small back-and-forth jitter within the dead zone → cursor barely moves.
        for i in 0 ..< 100 {
            let out = f.process(dx: i.isMultiple(of: 2) ? 0.3 : -0.3, dy: 0, dt: 0.008)
            total += out.dx
        }
        XCTAssertLessThan(abs(total), 0.5, "jitter should be damped to near zero")
    }

    func testSustainedMovementCatchesUp() {
        let f = TremorFilter(smoothing: 1.0, deadzone: 0.1)
        var total = 0.0
        // Deliberate sustained movement should pass through (cursor travels).
        for _ in 0 ..< 200 {
            total += f.process(dx: 5, dy: 0, dt: 0.008).dx
        }
        XCTAssertGreaterThan(total, 10, "deliberate movement must reach the cursor")
    }

    func testLargerMovementGivesLargerStep() {
        let small = TremorFilter(smoothing: 1.0, deadzone: 0.1)
        let large = TremorFilter(smoothing: 1.0, deadzone: 0.1)
        let s = small.process(dx: 2, dy: 0, dt: 0.008).dx
        let l = large.process(dx: 20, dy: 0, dt: 0.008).dx
        XCTAssertGreaterThan(l, s, "a faster movement should yield a larger step")
    }

    func testResetClearsState() {
        let f = TremorFilter(smoothing: 1.0, deadzone: 0.1)
        _ = f.process(dx: 50, dy: 30, dt: 0.008)
        f.reset()
        let out = f.process(dx: 0, dy: 0, dt: 0.008)
        XCTAssertEqual(out.dx, 0, accuracy: 1e-9)
        XCTAssertEqual(out.dy, 0, accuracy: 1e-9)
    }

    func testTremorSettingsResilientDecode() throws {
        let data = #"{"enabled": true}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(TremorSettings.self, from: data)
        XCTAssertTrue(s.enabled)
        XCTAssertEqual(s.smoothing, 1.0, accuracy: 1e-9, "missing key takes default")
    }
}
