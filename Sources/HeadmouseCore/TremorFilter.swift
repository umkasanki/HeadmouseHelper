import Foundation

/// 2D tremor-stabilization filter based on the **Angle Mouse** technique
/// (Wobbrock et al., CHI 2009 — "The Angle Mouse: Target-Agnostic Dynamic Gain
/// Adjustment Based on Angular Deviation"; algorithm cited in NOTICES.md).
///
/// It watches the *direction* of recent movement, not just speed: a straight
/// path (low angular deviation) is deliberate → full gain (passthrough); a
/// jittery, turning path (high angular deviation) is tremor → the gain is
/// dropped toward a floor, damping it. Because it applies a per-event gain in
/// [floor…1] it never lags intentional movement and needs no absolute target,
/// so it suits relative pixel deltas (unlike an integrate-to-target model).
public final class TremorFilter {
    /// Gain applied at maximum tremor (0…1). Lower = stronger damping.
    public var gainFloor: Double
    /// Per-event movements below this many pixels are suppressed.
    public var deadzone: Double

    private let sampleDistance = 8.0     // ΔD: pixels between sampled angles
    private let maxSamples = 16          // n: queued angles
    private let maxDeviationDeg = 120.0  // σθmax for n = 16

    private var angles: [Double] = []    // recent movement directions (radians)
    private var accumX = 0.0, accumY = 0.0

    public init(gainFloor: Double = 0.15, deadzone: Double = 0) {
        self.gainFloor = gainFloor
        self.deadzone = deadzone
    }

    public func configure(_ settings: TremorSettings) {
        // strength 0…1 → gainFloor 1…0.05 (0 = no damping).
        gainFloor = 1 - settings.strength * 0.95
        deadzone = settings.deadzone
    }

    public func reset() {
        angles.removeAll(keepingCapacity: true)
        accumX = 0; accumY = 0
    }

    /// Feed one raw movement (dx, dy); returns the movement to apply this event.
    /// (dt is unused — the gain is instantaneous.)
    public func process(dx: Double, dy: Double, dt _: Double = 0) -> (dx: Double, dy: Double) {
        if (dx * dx + dy * dy).squareRoot() < deadzone {
            return (0, 0)
        }

        // Sample a movement angle whenever we've travelled ΔD since the last one.
        accumX += dx
        accumY += dy
        if (accumX * accumX + accumY * accumY).squareRoot() >= sampleDistance {
            angles.append(atan2(accumY, accumX))
            if angles.count > maxSamples { angles.removeFirst() }
            accumX = 0; accumY = 0
        }

        let gain = currentGain()
        return (dx * gain, dy * gain)
    }

    /// Current C-D gain in [gainFloor…1] from the angular deviation of the queue.
    private func currentGain() -> Double {
        guard angles.count >= 2 else { return 1 }  // not enough data → passthrough
        let deviation = min(angularDeviationDegrees() / maxDeviationDeg, 1)
        return gainFloor + (1 - deviation) * (1 - gainFloor)
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

    /// Acute nonnegative angle between two angles, in [0…180] degrees (Eq. 3).
    private func angularDistanceDegrees(_ a: Double, _ b: Double) -> Double {
        let degrees = (a - b) * 180 / .pi
        let m = abs(degrees).truncatingRemainder(dividingBy: 360)
        return 180 - abs(m - 180)
    }
}
