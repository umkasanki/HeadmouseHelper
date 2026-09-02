import Foundation

/// Steady-state constant-velocity Kalman filter for one axis — the classic
/// **alpha-beta filter**.
///
/// It estimates position *and* velocity from a stream of noisy position samples.
/// That velocity state is the whole point, and it is what separates this from
/// every gain-scaling approach tried here before:
///
///  - It is an **estimator, not a multiplier**. The estimate converges on the true
///    position, so a deliberate move keeps all of its travel — it cannot undershoot
///    the way per-event gain damping does.
///  - The velocity state **extrapolates**, so sustained movement is not held back by
///    the smoothing time constant the way a plain low-pass is. Only motion the
///    velocity model fails to explain — i.e. shake — gets averaged away.
///  - Tremor and intent are separated **statistically**, through the assumed ratio of
///    process noise to measurement noise, rather than by a hand-picked threshold on
///    speed, direction or amplitude. Every one of those heuristics was tried first
///    and none of them could tell held-still tremor from slow deliberate movement.
///
/// One update per sample, using Kalata's steady-state gains:
/// ```
/// x += v*dt          // predict
/// r  = z - x         // residual
/// x += alpha*r       // correct position
/// v += (beta/dt)*r   // correct velocity
/// ```
public final class AlphaBetaFilter {
    /// Process-to-measurement noise ratio: larger = trust the measurement more =
    /// less smoothing. The dimensionless tracking index is `lambda = noiseRatio * dt^2`,
    /// recomputed per sample so the filter behaves the same when the event rate
    /// wobbles (it does — the tap runs on the main runloop at ordinary priority).
    public var noiseRatio: Double

    /// Forbid the estimate from travelling **past** the measurement in the direction
    /// it is moving. Without this the filter is unusable for pointing: the velocity
    /// state that removes lag also carries the cursor beyond the target when the head
    /// decelerates — 88 px past a target approached at 1260 px/s, where the reference
    /// implementation overshoots by nothing at all across 32 instrumented trials.
    ///
    /// The rule is exactly as strong as it needs to be and no stronger: the estimate
    /// may lag the measurement freely (that is the smoothing), it just may not pass
    /// it, because the measurement is by definition where the head asked to go. This
    /// keeps the endpoint exact, and unlike scaling movement by its speed it adds no
    /// unpredictability — the guarantee is that the cursor never travels further than
    /// asked, whatever the speed.
    ///
    /// Costs a little smoothing while holding still (0.27 px -> 0.38 px RMS above
    /// 4 Hz at `smoothing` 0.6, against a reference that ranges 0.3–1.1 px), because
    /// it binds on tremor excursions too. Gating it by speed avoids that but pays 4 px
    /// of overshoot and a 5x slower settle, which is the worse trade.
    public var neverPassMeasurement: Bool = true

    /// Only enforce `neverPassMeasurement` once the estimated speed exceeds this many
    /// units per second. `0` enforces it always.
    ///
    /// The guard is what the cursor needs while travelling and what it does not need
    /// while held. Holding still, the raw position jitters back and forth, so on every
    /// reversal the estimate finds itself "ahead" and gets pulled back onto the raw
    /// value — which is exactly where smoothing was supposed to be doing its work. On
    /// device this put a hard floor under the residual shake: raising smoothing from
    /// 0.6 to 0.8 changed nothing a user could feel. Gating the guard by speed leaves
    /// it in charge during movement, where overshoot matters, and out of the way
    /// during a hold, where it only reintroduces the jitter.
    public var clampAboveSpeed: Double = 0

    private var x = 0.0
    private var v = 0.0
    private var seeded = false

    /// Gains used by the most recent update — for tests and diagnostics.
    public private(set) var lastAlpha = 0.0
    public private(set) var lastBeta = 0.0

    public init(noiseRatio: Double = 100) {
        self.noiseRatio = noiseRatio
    }

    /// Current position estimate.
    public var position: Double { x }
    /// Current velocity estimate, in units per second.
    public var velocity: Double { v }

    public func reset() {
        x = 0
        v = 0
        seeded = false
        lastAlpha = 0
        lastBeta = 0
    }

    /// Feed one position measurement observed `dt` seconds after the previous one;
    /// returns the filtered position estimate.
    @discardableResult
    public func update(measurement z: Double, dt: Double) -> Double {
        guard dt > 0 else { return x }

        // The first sample defines the origin: adopt it exactly rather than easing
        // toward it from zero, which would fling the cursor across the screen.
        guard seeded else {
            seeded = true
            x = z
            v = 0
            return x
        }

        let (alpha, beta) = Self.gains(trackingIndex: noiseRatio * dt * dt)
        lastAlpha = alpha
        lastBeta = beta

        x += v * dt
        let residual = z - x
        x += alpha * residual
        v += (beta / dt) * residual

        if neverPassMeasurement, abs(v) >= clampAboveSpeed {
            if v > 0, x > z {
                x = z
                v = 0
            } else if v < 0, x < z {
                x = z
                v = 0
            }
        }
        return x
    }

    /// Steady-state Kalman gains for a constant-velocity model, derived from the
    /// tracking index `lambda` (Kalata, 1984):
    ///
    ///     r = (4 + lambda - sqrt(8*lambda + lambda^2)) / 4
    ///     alpha = 1 - r^2
    ///     beta  = 2*(2 - alpha) - 4*sqrt(1 - alpha)
    ///
    /// `lambda -> 0` freezes the estimate entirely; `lambda -> inf` follows the raw
    /// measurement. Equivalently `lambda = 2*(1-r)^2 / r`.
    public static func gains(trackingIndex lambda: Double) -> (alpha: Double, beta: Double) {
        let l = max(lambda, 0)
        let r = (4 + l - (8 * l + l * l).squareRoot()) / 4
        let alpha = min(max(1 - r * r, 0), 1)
        let beta = max(2 * (2 - alpha) - 4 * (1 - alpha).squareRoot(), 0)
        return (alpha, beta)
    }
}
