import Foundation

/// One Euro Filter (Casiez, Roussel & Vogel — "1€ Filter: A Simple Speed-based
/// Low-pass Filter for Noisy Input in Interactive Systems", CHI 2012).
///
/// A speed-adaptive low-pass on a 1D signal: it smooths heavily when the signal
/// moves slowly (killing tremor) and lightly when it moves fast (keeping
/// intentional motion responsive). Because it filters the *value* (here, cursor
/// position) rather than scaling each increment, a sustained deliberate move
/// reaches its true endpoint — no travel distance is lost.
public final class OneEuroFilter {
    /// Cutoff frequency (Hz) at zero speed. Lower = smoother when still.
    public var minCutoff: Double
    /// Speed coefficient. Higher = cutoff rises faster with speed = less lag when
    /// moving fast.
    public var beta: Double
    /// Cutoff frequency (Hz) for the internal speed (derivative) estimate.
    public var dCutoff: Double

    private var hasPrev = false
    private var xPrev = 0.0
    private var dxPrev = 0.0

    public init(minCutoff: Double = 1.0, beta: Double = 0.02, dCutoff: Double = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }

    public func reset() {
        hasPrev = false
        xPrev = 0
        dxPrev = 0
    }

    /// Filter one sample `x` observed `dt` seconds after the previous one.
    public func filter(_ x: Double, dt: Double) -> Double {
        guard dt > 0 else { return x }
        guard hasPrev else {
            hasPrev = true
            xPrev = x
            dxPrev = 0
            return x
        }

        let dx = (x - xPrev) / dt
        let dxHat = lowpass(dx, prev: dxPrev, alpha: alpha(cutoff: dCutoff, dt: dt))
        let cutoff = minCutoff + beta * abs(dxHat)
        let xHat = lowpass(x, prev: xPrev, alpha: alpha(cutoff: cutoff, dt: dt))

        xPrev = xHat
        dxPrev = dxHat
        return xHat
    }

    private func alpha(cutoff: Double, dt: Double) -> Double {
        let tau = 1.0 / (2.0 * .pi * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }

    private func lowpass(_ x: Double, prev: Double, alpha: Double) -> Double {
        alpha * x + (1 - alpha) * prev
    }
}
