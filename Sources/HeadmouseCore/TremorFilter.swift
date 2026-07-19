import Foundation

/// 2D tremor-stabilization filter, modelled on how proven assistive tools work
/// (e.g. SteadyMouse: a low-pass that strips high-frequency tremor while keeping
/// low-frequency intent) plus a **dwell freeze** for clicking.
///
/// Two stages:
///  1. **Second-order low-pass** on the accumulated cursor position — smooths the
///     tremor. A 2-pole cascade rolls off high-frequency shake far more sharply
///     than a single pole for the same lag.
///  2. **Dwell freeze** — the piece that makes clicking possible. Hold-tremor and
///     slow deliberate movement look almost identical by per-event speed/size; the
///     one thing that separates them is *net progress over time*. If the summed
///     movement over a short window stays inside a small radius (you're topping in
///     place), the cursor is frozen so you can click; once you actually travel, it
///     passes at full gain. This does not permanently slow movement — it only
///     engages when you stop going anywhere.
///
/// - `oneEuro`: 2nd-order low-pass + dwell freeze (recommended).
/// - `ewma`: plain exponential low-pass, no freeze — a simple baseline for A/B.
public final class TremorFilter {
    public var algorithm: TremorAlgorithm = .oneEuro
    /// Per-event movements below this many pixels are suppressed. 0 = off.
    public var deadzone: Double

    /// Master strength 0…1: more low-pass smoothing + a larger dwell radius.
    private var strength = 0.5

    // Second-order low-pass state (two cascaded one-pole stages) on position.
    private var rawX = 0.0, rawY = 0.0
    private var lp1X = 0.0, lp1Y = 0.0
    private var lp2X = 0.0, lp2Y = 0.0
    private var prevX = 0.0, prevY = 0.0
    private var seeded = false

    // Dwell window: recent raw movement, to measure net progress.
    private let windowSeconds = 0.3
    private var recent: [(dx: Double, dy: Double, age: Double)] = []
    // Freeze state machine (hysteresis so a brief mid-move pause never freezes).
    private var moving = true
    private var quietTime = 0.0
    private var gainState = 1.0

    // EWMA baseline state.
    private var alpha = 0.3
    private var smoothedX = 0.0, smoothedY = 0.0

    // Diagnostics (read by the app's debug logging).
    public private(set) var lastNetDisp = 0.0
    public private(set) var lastGain = 1.0

    public init(deadzone: Double = 0) {
        self.deadzone = deadzone
    }

    /// Strength is the master knob: higher = heavier low-pass + a larger "you're
    /// holding still" radius (freezes more readily, needs more decisive movement
    /// to release).
    public func configure(_ settings: TremorSettings) {
        if algorithm != settings.algorithm { reset() }  // clear carryover on switch
        algorithm = settings.algorithm
        deadzone = settings.deadzone
        strength = min(max(settings.strength, 0), 1)
        alpha = 1 - strength * 0.9   // s 1 → alpha 0.1 (smooth) for EWMA
    }

    public func reset() {
        rawX = 0; rawY = 0
        lp1X = 0; lp1Y = 0; lp2X = 0; lp2Y = 0
        prevX = 0; prevY = 0; seeded = false
        recent.removeAll(keepingCapacity: true)
        moving = true; quietTime = 0; gainState = 1
        smoothedX = 0; smoothedY = 0
        lastNetDisp = 0; lastGain = 1
    }

    /// Feed one raw movement (dx, dy) over `dt` seconds; returns the movement to
    /// apply this event.
    public func process(dx: Double, dy: Double, dt: Double = 0) -> (dx: Double, dy: Double) {
        if (dx * dx + dy * dy).squareRoot() < deadzone {
            return (0, 0)
        }

        if algorithm == .ewma {
            smoothedX = alpha * dx + (1 - alpha) * smoothedX
            smoothedY = alpha * dy + (1 - alpha) * smoothedY
            return (smoothedX, smoothedY)
        }

        let effDt = dt > 0 ? dt : 0.008

        // --- Stage 1: second-order low-pass on the accumulated position. ---
        rawX += dx; rawY += dy
        if !seeded {
            seeded = true
            lp1X = rawX; lp1Y = rawY; lp2X = rawX; lp2Y = rawY
            prevX = rawX; prevY = rawY
        }
        let fc = 6.0 - strength * 5.0                 // s 0 → 6 Hz (light), s 1 → 1 Hz (heavy)
        let a = 1.0 / (1.0 + (1.0 / (2.0 * .pi * fc)) / effDt)
        lp1X += a * (rawX - lp1X); lp1Y += a * (rawY - lp1Y)
        lp2X += a * (lp1X - lp2X); lp2Y += a * (lp1Y - lp2Y)
        let edx = lp2X - prevX
        let edy = lp2Y - prevY
        prevX = lp2X; prevY = lp2Y

        // --- Stage 2: dwell freeze from net progress over the window. ---
        let gain = dwellGain(dx: dx, dy: dy, dt: effDt)

        return (edx * gain, edy * gain)
    }

    /// Freeze when the user is holding still, pass when travelling — with
    /// hysteresis so a brief mid-move pause never freezes (that caused the
    /// stop-and-jump stutter), and an eased gain so it never snaps 0↔1.
    private func dwellGain(dx: Double, dy: Double, dt: Double) -> Double {
        recent.append((dx, dy, 0))
        for i in recent.indices { recent[i].age += dt }
        while let first = recent.first, first.age > windowSeconds { recent.removeFirst() }

        var netX = 0.0, netY = 0.0
        for r in recent { netX += r.dx; netY += r.dy }
        let net = (netX * netX + netY * netY).squareRoot()
        lastNetDisp = net

        let lockRadius = 3.0 + strength * 8.0        // s 0.7 → ~8.6 px
        let releaseRadius = lockRadius + 12.0
        let settleTime = 0.25                        // must be quiet this long to freeze

        if moving {
            // Only freeze after sustained quiet — brief pauses mid-move don't count.
            quietTime = net < lockRadius ? quietTime + dt : 0
            if quietTime >= settleTime { moving = false }
        } else if net > releaseRadius {
            moving = true
            quietTime = 0
        }

        // Ease the gain toward the target (τ ≈ 40 ms) so transitions are smooth.
        let target = moving ? 1.0 : 0.0
        let ga = dt / (dt + 0.04)
        gainState += ga * (target - gainState)
        lastGain = gainState
        return gainState
    }

    private func smoothstep(_ x: Double, _ a: Double, _ b: Double) -> Double {
        guard b > a else { return x >= b ? 1 : 0 }
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
