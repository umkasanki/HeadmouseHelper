import XCTest
@testable import HeadmouseCore

final class TremorFilterTests: XCTestCase {
    private let dt = 0.008   // ~120 Hz event rate

    // MARK: - Dwell freeze: travel passes, topping-in-place freezes.

    func testTravelPasses() {
        let f = TremorFilter()
        f.configure(TremorSettings(enabled: true, algorithm: .oneEuro, strength: 0.7))
        var out = (dx: 0.0, dy: 0.0)
        for _ in 0 ..< 80 { out = f.process(dx: 10, dy: 0, dt: dt) }   // real, sustained travel
        XCTAssertEqual(out.dx, 10, accuracy: 1.0, "deliberate travel passes at full gain")
    }

    func testHoldJitterIsFrozen() {
        let f = TremorFilter()
        f.configure(TremorSettings(enabled: true, algorithm: .oneEuro, strength: 0.7))
        var out = (dx: 0.0, dy: 0.0)
        // Wander around a point: net displacement stays tiny → should freeze.
        let pattern = [3.0, -2, 2, -3, 1, -1, 2, -2]
        for i in 0 ..< 120 { out = f.process(dx: pattern[i % pattern.count], dy: 0, dt: dt) }
        XCTAssertLessThan(abs(out.dx), 0.6, "topping in place is frozen so the cursor can be held for a click")
    }

    func testDecisiveMovePassesAtLowStrength() {
        let f = TremorFilter()
        f.configure(TremorSettings(enabled: true, algorithm: .oneEuro, strength: 0.2))
        var out = (dx: 0.0, dy: 0.0)
        for _ in 0 ..< 60 { out = f.process(dx: 15, dy: 0, dt: dt) }
        XCTAssertEqual(out.dx, 15, accuracy: 1.5, "decisive travel passes even at low strength")
    }

    func testTravelPreservesDistance() {
        let f = TremorFilter()
        f.configure(TremorSettings(enabled: true, algorithm: .oneEuro, strength: 0.7))
        var total = 0.0
        for _ in 0 ..< 60 { total += f.process(dx: 20, dy: 0, dt: dt).dx }   // 1200 px traveled
        for _ in 0 ..< 200 { total += f.process(dx: 0, dy: 0, dt: dt).dx }
        XCTAssertGreaterThan(total, 1100, "a real move keeps essentially all its distance")
    }

    func testResetClearsHistory() {
        let f = TremorFilter()
        f.configure(TremorSettings(enabled: true, algorithm: .oneEuro, strength: 0.7))
        for _ in 0 ..< 40 { _ = f.process(dx: 20, dy: 0, dt: dt) }
        f.reset()
        XCTAssertEqual(f.lastGain, 1.0, accuracy: 1e-9, "reset clears dwell/low-pass state")
    }

    func testDeadzoneSuppressesTinyMovement() {
        let f = TremorFilter()
        f.configure(TremorSettings(enabled: true, algorithm: .oneEuro, strength: 0.5, deadzone: 5))
        let out = f.process(dx: 2, dy: 0, dt: dt)
        XCTAssertEqual(out.dx, 0, accuracy: 1e-9)
        XCTAssertEqual(out.dy, 0, accuracy: 1e-9)
    }

    // MARK: - EWMA baseline

    func testEwmaDampsJitter() {
        let f = TremorFilter()
        f.configure(TremorSettings(enabled: true, algorithm: .ewma, strength: 0.8))
        var last = 0.0
        for i in 0 ..< 40 { last = f.process(dx: i.isMultiple(of: 2) ? 10 : -10, dy: 0, dt: dt).dx }
        XCTAssertLessThan(abs(last), 5, "EWMA averages out alternating jitter")
    }

    func testEwmaPreservesTotalTravel() {
        let f = TremorFilter()
        f.configure(TremorSettings(enabled: true, algorithm: .ewma, strength: 0.8))
        var total = 0.0
        for _ in 0 ..< 20 { total += f.process(dx: 10, dy: 0, dt: dt).dx }
        for _ in 0 ..< 400 { total += f.process(dx: 0, dy: 0, dt: dt).dx }
        XCTAssertEqual(total, 200, accuracy: 1.0, "EWMA also preserves total travel")
    }

    // MARK: - Settings

    func testTremorSettingsResilientDecode() throws {
        let s = try JSONDecoder().decode(TremorSettings.self, from: #"{"enabled": true}"#.data(using: .utf8)!)
        XCTAssertTrue(s.enabled)
        XCTAssertEqual(s.algorithm, .oneEuro, "missing algorithm takes default")
        XCTAssertEqual(s.strength, 0.5, accuracy: 1e-9, "missing key takes default")
    }

    func testUnknownAlgorithmFallsBackToDefault() throws {
        let s = try JSONDecoder().decode(
            TremorSettings.self,
            from: #"{"enabled": true, "algorithm": "angleMouse"}"#.data(using: .utf8)!
        )
        XCTAssertEqual(s.algorithm, .oneEuro)
    }
}
