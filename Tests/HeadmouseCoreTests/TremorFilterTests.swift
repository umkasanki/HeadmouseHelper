import XCTest
@testable import HeadmouseCore

final class TremorFilterTests: XCTestCase {
    func testNotEnoughSamplesPassesThrough() {
        let f = TremorFilter(gainFloor: 0.1, deadzone: 0)
        let out = f.process(dx: 3, dy: 0)
        XCTAssertEqual(out.dx, 3, accuracy: 1e-9, "no angle history yet → passthrough")
    }

    func testStraightMovementPassesThrough() {
        let f = TremorFilter(gainFloor: 0.1, deadzone: 0)
        // Warm up with a straight path — every event moves in the same direction.
        for _ in 0 ..< 30 { _ = f.process(dx: 10, dy: 0) }
        let out = f.process(dx: 10, dy: 0)
        XCTAssertEqual(out.dx, 10, accuracy: 0.01, "straight path → gain ≈ 1")
    }

    func testJitteryMovementIsDamped() {
        let f = TremorFilter(gainFloor: 0.1, deadzone: 0)
        // Alternating direction = high angular deviation = tremor.
        for i in 0 ..< 30 { _ = f.process(dx: i.isMultiple(of: 2) ? 10 : -10, dy: 0) }
        let out = f.process(dx: 10, dy: 0)
        XCTAssertLessThan(abs(out.dx), 5, "jittery path → gain dropped toward the floor")
    }

    func testDeadzoneSuppressesTinyMovement() {
        let f = TremorFilter(gainFloor: 0.1, deadzone: 5)
        let out = f.process(dx: 2, dy: 0)
        XCTAssertEqual(out.dx, 0, accuracy: 1e-9)
        XCTAssertEqual(out.dy, 0, accuracy: 1e-9)
    }

    func testResetClearsHistory() {
        let f = TremorFilter(gainFloor: 0.1, deadzone: 0)
        for i in 0 ..< 30 { _ = f.process(dx: i.isMultiple(of: 2) ? 10 : -10, dy: 0) }
        f.reset()
        let out = f.process(dx: 7, dy: 0)
        XCTAssertEqual(out.dx, 7, accuracy: 1e-9, "after reset → passthrough again")
    }

    func testStrengthZeroMeansNoDamping() {
        let f = TremorFilter()
        f.configure(TremorSettings(enabled: true, strength: 0, deadzone: 0))
        for i in 0 ..< 30 { _ = f.process(dx: i.isMultiple(of: 2) ? 10 : -10, dy: 0) }
        let out = f.process(dx: 10, dy: 0)
        XCTAssertEqual(out.dx, 10, accuracy: 0.01, "strength 0 → gain floor 1 → no damping")
    }

    func testTremorSettingsResilientDecode() throws {
        let s = try JSONDecoder().decode(TremorSettings.self, from: #"{"enabled": true}"#.data(using: .utf8)!)
        XCTAssertTrue(s.enabled)
        XCTAssertEqual(s.algorithm, .angleMouse, "missing algorithm takes default")
        XCTAssertEqual(s.strength, 0.5, accuracy: 1e-9, "missing key takes default")
    }

    // MARK: - Speed algorithm

    func testSpeedDampsSlowMovement() {
        let f = TremorFilter()
        f.configure(TremorSettings(enabled: true, algorithm: .speed, strength: 0.5))
        let out = f.process(dx: 1, dy: 0, dt: 0.1)   // 10 px/s → slow
        XCTAssertLessThan(out.dx, 1, "slow movement is damped")
    }

    func testSpeedPassesFastMovement() {
        let f = TremorFilter()
        f.configure(TremorSettings(enabled: true, algorithm: .speed, strength: 0.5))
        let out = f.process(dx: 100, dy: 0, dt: 0.1)  // 1000 px/s → fast
        XCTAssertEqual(out.dx, 100, accuracy: 0.01, "fast movement passes through")
    }

    // MARK: - EWMA algorithm

    func testEwmaDampsJitter() {
        let f = TremorFilter()
        f.configure(TremorSettings(enabled: true, algorithm: .ewma, strength: 0.8))
        var last = 0.0
        for i in 0 ..< 40 { last = f.process(dx: i.isMultiple(of: 2) ? 10 : -10, dy: 0, dt: 0.008).dx }
        XCTAssertLessThan(abs(last), 5, "EWMA averages out alternating jitter")
    }

    // MARK: - Hybrid algorithm

    func testHybridPassesFastEvenIfJittery() {
        let f = TremorFilter()
        f.configure(TremorSettings(enabled: true, algorithm: .hybrid, strength: 0.5))
        var out = (dx: 0.0, dy: 0.0)
        for i in 0 ..< 20 { out = f.process(dx: i.isMultiple(of: 2) ? 100 : -100, dy: 0, dt: 0.05) }
        XCTAssertEqual(abs(out.dx), 100, accuracy: 0.01, "fast movement passes even when jittery")
    }
}
