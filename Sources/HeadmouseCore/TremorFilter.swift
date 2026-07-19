import Foundation

/// 2D tremor-stabilization filter with several switchable algorithms so they can
/// be A/B compared (see `TremorAlgorithm`). All operate on relative pixel deltas
/// per event and never lag intentional movement more than the model requires.
///
/// - `angleMouse` (Wobbrock, CHI 2009): per-event gain in [floor…1] from the
///   angular deviation of the recent path — straight = deliberate = full gain,
///   jittery = tremor = damped. (Algorithm cited in NOTICES.md.)
/// - `speed`: gain from movement speed — slow damped, fast passed.
/// - `ewma`: exponential low-pass on the delta stream — smooths jitter, adds lag.
/// - `hybrid`: full gain if the path is straight OR fast; damps only slow AND
///   jittery movement.
public final class TremorFilter {
    public var algorithm: TremorAlgorithm = .angleMouse
    /// Gain applied at maximum tremor (0…1) for angle/speed/hybrid.
    public var gainFloor: Double
    /// EWMA smoothing factor (0…1); lower = smoother / more lag.
    public var alpha: Double
    /// Per-event movements below this many pixels are suppressed.
    public var deadzone: Double

    // Angle Mouse machinery.
    private let sampleDistance = 8.0
    private let maxSamples = 16
    private let maxDeviationDeg = 120.0
    private var angles: [Double] = []
    private var accumX = 0.0, accumY = 0.0

    // Speed thresholds (pixels/second): below lo → fully "slow", above hi → "fast".
    private let speedLo = 60.0
    private let speedHi = 600.0

    // EWMA state.
    private var smoothedX = 0.0, smoothedY = 0.0

    public init(gainFloor: Double = 0.15, alpha: Double = 0.3, deadzone: Double = 0) {
        self.gainFloor = gainFloor
        self.alpha = alpha
        self.deadzone = deadzone
    }

    public func configure(_ settings: TremorSettings) {
        algorithm = settings.algorithm
        gainFloor = 1 - settings.strength * 0.95   // strength 1 → floor 0.05
        alpha = 1 - settings.strength * 0.9        // strength 1 → alpha 0.1 (smooth)
        deadzone = settings.deadzone
    }

    public func reset() {
        angles.removeAll(keepingCapacity: true)
        accumX = 0; accumY = 0
        smoothedX = 0; smoothedY = 0
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

        sampleAngle(dx: dx, dy: dy)
        let gain = gainFloor + (1 - gainFloor) * intentSignal(dx: dx, dy: dy, dt: dt)
        return (dx * gain, dy * gain)
    }

    /// 0…1 — how much the movement looks intentional (1 = keep full gain).
    private func intentSignal(dx: Double, dy: Double, dt: Double) -> Double {
        switch algorithm {
        case .speed: return fastness(dx: dx, dy: dy, dt: dt)
        case .hybrid: return max(straightness(), fastness(dx: dx, dy: dy, dt: dt))
        default: return straightness()   // angleMouse
        }
    }

    private func straightness() -> Double {
        guard angles.count >= 2 else { return 1 }
        return 1 - min(angularDeviationDegrees() / maxDeviationDeg, 1)
    }

    private func fastness(dx: Double, dy: Double, dt: Double) -> Double {
        guard dt > 1e-6 else { return 1 }
        let speed = (dx * dx + dy * dy).squareRoot() / dt
        return min(max((speed - speedLo) / (speedHi - speedLo), 0), 1)
    }

    private func sampleAngle(dx: Double, dy: Double) {
        accumX += dx
        accumY += dy
        if (accumX * accumX + accumY * accumY).squareRoot() >= sampleDistance {
            angles.append(atan2(accumY, accumX))
            if angles.count > maxSamples { angles.removeFirst() }
            accumX = 0; accumY = 0
        }
    }

    private func angularDeviationDegrees() -> Double {
        var mx = 0.0, my = 0.0
        for a in angles { mx += cos(a); my += sin(a) }
        let mean = atan2(my, mx)

        var sumSquares = 0.0
        for a in angles {
            let d = angularDistanceDegrees(a, mean)
            sumSquares += d * d
        }
        return (sumSquares / Double(angles.count - 1)).squareRoot()
    }

    /// Acute nonnegative angle between two angles, in [0…180] degrees.
    private func angularDistanceDegrees(_ a: Double, _ b: Double) -> Double {
        let degrees = (a - b) * 180 / .pi
        let m = abs(degrees).truncatingRemainder(dividingBy: 360)
        return 180 - abs(m - 180)
    }
}
