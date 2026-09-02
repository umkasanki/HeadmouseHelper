import XCTest
@testable import HeadmouseCore

final class TremorFilterTests: XCTestCase {
    private let dt = 0.008   // 125 Hz — the HeadMouse Nano's report rate

    // MARK: - The two properties that every earlier filter failed

    /// Failure #1 of the earlier attempts: a per-event gain multiplier permanently
    /// discards part of every movement, so the cursor undershoots its target. A
    /// position estimator cannot do that — it converges on the measurement.
    func testPreservesTotalTravelExactly() {
        let f = TremorFilter()
        f.configure(TremorSettings(enabled: true, smoothing: 0.8))

        var total = 0.0
        for _ in 0 ..< 200 { total += f.process(dx: 12, dy: 0, dt: dt).dx }   // 2400 px asked for
        for _ in 0 ..< 1500 { total += f.process(dx: 0, dy: 0, dt: dt).dx }   // then hold still

        XCTAssertEqual(total, 2400, accuracy: 1.0, "the cursor ends up exactly where the head asked")
    }

    /// Failure #2: a plain low-pass lags sustained movement by its whole time
    /// constant. The velocity state extrapolates, so a constant-velocity move is
    /// tracked with essentially no lag — at these settings a first-order low-pass of
    /// comparable smoothness would sit well over 100 px behind.
    func testNoLagOnSustainedMovement() {
        let f = TremorFilter()
        f.configure(TremorSettings(enabled: true, smoothing: 0.6))

        var output = 0.0
        var input = 0.0
        for _ in 0 ..< 800 {
            input += 10
            output += f.process(dx: 10, dy: 0, dt: dt).dx
        }

        XCTAssertEqual(output, input, accuracy: 20, "steady movement is tracked without falling behind")
    }

    /// Aim at a target, decelerate onto it, stop. Returns the cursor's position
    /// relative to where the head asked it to be, sample by sample, plus the index at
    /// which the head finished moving.
    private func approachAndStop(
        _ filter: TremorFilter, speed: Double = 1260, decelerate: Double = 0.15
    ) -> (error: [Double], stoppedAt: Int) {
        let cruise = Int(0.5 / dt), slowing = Int(decelerate / dt), after = Int(2.0 / dt)
        var asked = 0.0, got = 0.0, error: [Double] = []
        for i in 0 ..< (cruise + slowing + after) {
            let v: Double
            if i < cruise {
                v = speed
            } else if i < cruise + slowing {
                v = speed * (1 - Double(i - cruise + 1) / Double(slowing))
            } else {
                v = 0
            }
            asked += v * dt
            got += filter.process(dx: v * dt, dy: 0, dt: dt).dx
            error.append(got - asked)
        }
        return (error, cruise + slowing)
    }

    /// The third failure mode, and the one the user named as decisive: every movement
    /// is aimed at a UI element, so the cursor must not sail past it. The reference
    /// implementation overshoots by nothing at all across 32 instrumented trials.
    func testNeverOvershootsTheTarget() {
        for smoothing in [0.4, 0.6, 0.8] {
            let f = TremorFilter()
            f.configure(TremorSettings(enabled: true, smoothing: smoothing))
            let overshoot = approachAndStop(f).error.max() ?? 0
            XCTAssertLessThanOrEqual(overshoot, 1.0,
                                     "smoothing \(smoothing): cursor travelled past where the head aimed")
        }
    }

    func testLandsExactlyWhereAimed() {
        let f = TremorFilter()
        f.configure(TremorSettings(enabled: true, smoothing: 0.6))
        let final = approachAndStop(f).error.last ?? .infinity
        XCTAssertEqual(final, 0, accuracy: 0.5)
    }

    func testSettlesOnTargetQuickly() {
        let f = TremorFilter()
        f.configure(TremorSettings(enabled: true, smoothing: 0.6))
        let (error, stoppedAt) = approachAndStop(f)
        let settled = (stoppedAt ..< error.count).first { i in
            error[i...].allSatisfy { abs($0) <= 2 }
        }
        XCTAssertNotNil(settled, "cursor never came to rest on the target")
        let ms = Double(settled! - stoppedAt) * dt * 1000
        XCTAssertLessThanOrEqual(ms, 300, "settling took \(Int(ms)) ms; the reference dwells 300-550 ms before clicking")
    }

    /// Characterisation test: without the guard the textbook filter is unusable for
    /// pointing. Kept so that anyone tempted to drop `neverPassMeasurement` sees the
    /// size of what it is holding back.
    func testWithoutTheGuardTheTextbookFilterOvershootsBadly() {
        let f = TremorFilter()
        f.configure(TremorSettings(enabled: true, smoothing: 0.6))
        f.neverPassMeasurement = false
        let overshoot = approachAndStop(f).error.max() ?? 0
        XCTAssertGreaterThan(overshoot, 50, "the guard is what keeps the cursor on target")
    }

    // MARK: - Tremor suppression

    func testHoldJitterIsSmoothedAway() {
        let f = TremorFilter()
        f.configure(TremorSettings(enabled: true, smoothing: 0.8))

        // Shake in place: the raw position bounces over a 3 px span and goes nowhere.
        var minOut = Double.infinity, maxOut = -Double.infinity
        for i in 0 ..< 400 {
            let out = f.process(dx: i.isMultiple(of: 2) ? 3 : -3, dy: 0, dt: dt).dx
            if i > 200 {
                minOut = min(minOut, out)
                maxOut = max(maxOut, out)
            }
        }

        XCTAssertLessThan(maxOut - minOut, 1.0, "3 px of shake comes out as well under a pixel")
    }

    func testMoreSmoothingSuppressesMoreJitter() {
        func residualShake(smoothing: Double) -> Double {
            let f = TremorFilter()
            f.configure(TremorSettings(enabled: true, smoothing: smoothing))
            var peak = 0.0
            for i in 0 ..< 400 {
                let out = f.process(dx: i.isMultiple(of: 2) ? 3 : -3, dy: 0, dt: dt).dx
                if i > 200 { peak = max(peak, abs(out)) }
            }
            return peak
        }

        let light = residualShake(smoothing: 0.2)
        let heavy = residualShake(smoothing: 0.9)
        XCTAssertLessThan(heavy, light, "the slider actually does something across its range")
    }

    // MARK: - Per-axis independence

    func testAxesAreFilteredIndependently() {
        let f = TremorFilter()
        f.configure(TremorSettings(
            enabled: true, smoothing: 0.1, verticalSmoothing: 0.95, linkAxes: false
        ))

        var peakX = 0.0, peakY = 0.0
        for i in 0 ..< 400 {
            let jitter = i.isMultiple(of: 2) ? 3.0 : -3.0
            let out = f.process(dx: jitter, dy: jitter, dt: dt)
            if i > 200 {
                peakX = max(peakX, abs(out.dx))
                peakY = max(peakY, abs(out.dy))
            }
        }

        XCTAssertLessThan(peakY, peakX, "vertical can be smoothed harder than horizontal")
    }

    func testLinkedAxesUseTheHorizontalValue() {
        let s = TremorSettings(smoothing: 0.3, verticalSmoothing: 0.9, linkAxes: true)
        XCTAssertEqual(s.effectiveVerticalSmoothing, 0.3, accuracy: 1e-9)
    }

    // MARK: - State

    func testResetClearsState() {
        let f = TremorFilter()
        f.configure(TremorSettings(enabled: true, smoothing: 0.6))
        for _ in 0 ..< 100 { _ = f.process(dx: 20, dy: 5, dt: dt) }
        f.reset()

        XCTAssertEqual(f.velocityX, 0, accuracy: 1e-9)
        XCTAssertEqual(f.velocityY, 0, accuracy: 1e-9)
        // After a reset the next event seeds the estimate rather than easing toward
        // it from the origin, which would fling the cursor across the screen.
        let out = f.process(dx: 7, dy: -4, dt: dt)
        XCTAssertEqual(out.dx, 7, accuracy: 1e-9)
        XCTAssertEqual(out.dy, -4, accuracy: 1e-9)
    }

    // MARK: - Slider mapping

    func testSmoothingMapsMonotonicallyOntoNoiseRatio() {
        let ends = (TremorFilter.noiseRatio(forSmoothing: 0), TremorFilter.noiseRatio(forSmoothing: 1))
        XCTAssertEqual(ends.0, TremorFilter.lightNoiseRatio, accuracy: 1e-6)
        XCTAssertEqual(ends.1, TremorFilter.heavyNoiseRatio, accuracy: 1e-6)

        var previous = Double.infinity
        for step in 0 ... 10 {
            let ratio = TremorFilter.noiseRatio(forSmoothing: Double(step) / 10)
            XCTAssertLessThan(ratio, previous, "more smoothing always means a lower noise ratio")
            previous = ratio
        }
    }

    func testSmoothingIsClampedToRange() {
        XCTAssertEqual(TremorFilter.noiseRatio(forSmoothing: -5), TremorFilter.lightNoiseRatio, accuracy: 1e-6)
        XCTAssertEqual(TremorFilter.noiseRatio(forSmoothing: 5), TremorFilter.heavyNoiseRatio, accuracy: 1e-6)
    }

    // MARK: - Kalata gains

    func testGainsSpanTheFullRange() {
        let frozen = AlphaBetaFilter.gains(trackingIndex: 0)
        XCTAssertEqual(frozen.alpha, 0, accuracy: 1e-9, "lambda = 0 freezes the estimate")
        XCTAssertEqual(frozen.beta, 0, accuracy: 1e-9)

        let free = AlphaBetaFilter.gains(trackingIndex: 1e9)
        XCTAssertEqual(free.alpha, 1, accuracy: 1e-3, "a huge lambda follows the measurement")
    }

    func testGainsAreMonotonicInTrackingIndex() {
        var previousAlpha = -1.0
        for exponent in stride(from: -6.0, through: 2.0, by: 0.5) {
            let alpha = AlphaBetaFilter.gains(trackingIndex: pow(10, exponent)).alpha
            XCTAssertGreaterThan(alpha, previousAlpha)
            XCTAssertTrue((0 ... 1).contains(alpha))
            previousAlpha = alpha
        }
    }

    /// Kalata's relation inverted: lambda = 2*(1-r)^2 / r, with alpha = 1 - r^2.
    func testGainsMatchTheClosedForm() {
        for r in [0.99, 0.95, 0.8, 0.5] {
            let lambda = 2 * pow(1 - r, 2) / r
            XCTAssertEqual(AlphaBetaFilter.gains(trackingIndex: lambda).alpha,
                           1 - r * r, accuracy: 1e-9)
        }
    }

    // MARK: - Settings

    func testResilientDecodeTakesDefaults() throws {
        let s = try JSONDecoder().decode(TremorSettings.self, from: #"{"enabled": true}"#.data(using: .utf8)!)
        XCTAssertTrue(s.enabled)
        XCTAssertEqual(s.smoothing, TremorSettings().smoothing, accuracy: 1e-9)
        XCTAssertTrue(s.linkAxes)
        XCTAssertFalse(s.trace)
    }

    func testLegacyStrengthKeyIsMigrated() throws {
        // Written by a pre-Kalman build: keep the user's level instead of resetting it.
        let json = #"{"enabled": true, "algorithm": "oneEuro", "strength": 0.85, "deadzone": 3}"#
        let s = try JSONDecoder().decode(TremorSettings.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(s.smoothing, 0.85, accuracy: 1e-9)
        XCTAssertEqual(s.verticalSmoothing, 0.85, accuracy: 1e-9, "vertical follows unless told otherwise")
    }

    func testSettingsRoundTrip() throws {
        let original = TremorSettings(
            enabled: true, smoothing: 0.42, verticalSmoothing: 0.77, linkAxes: false, trace: true
        )
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(TremorSettings.self, from: data), original)
    }

    func testOutOfRangeSmoothingIsClamped() {
        XCTAssertEqual(TremorSettings(smoothing: 3).smoothing, 1, accuracy: 1e-9)
        XCTAssertEqual(TremorSettings(smoothing: -1).smoothing, 0, accuracy: 1e-9)
    }
}
