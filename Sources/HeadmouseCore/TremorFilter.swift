import Foundation

/// Two-axis tremor stabilization: an independent `AlphaBetaFilter` per axis running
/// over the *accumulated position* of the incoming pointer deltas.
///
/// Working in position rather than in per-event gain is what preserves travel. The
/// estimate is unbiased and converges on the measured position, so once a movement
/// settles the cursor has gone exactly as far as the head asked for — no undershoot,
/// no distance quietly lost to a damping factor.
///
/// The axes are filtered separately (not as a 2D vector) both because that is what a
/// diagonal-covariance Kalman reduces to, and because vertical head movement needs
/// its own smoothing level in practice.
public final class TremorFilter {
    /// Noise ratio at `smoothing == 0` — light filtering, near passthrough.
    static let lightNoiseRatio = 5000.0
    /// Noise ratio at `smoothing == 1` — heavy filtering.
    static let heavyNoiseRatio = 1.5

    /// Event interval assumed when the caller cannot supply one (the HeadMouse Nano
    /// reports at 125 Hz).
    private static let nominalDt = 0.008

    private let filterX = AlphaBetaFilter()
    private let filterY = AlphaBetaFilter()

    // Accumulated raw input position (the measurement) and the last estimate we
    // emitted, whose difference is the movement handed back to the caller.
    private var rawX = 0.0, rawY = 0.0
    private var prevEstimateX = 0.0, prevEstimateY = 0.0

    public init() {}

    /// See `AlphaBetaFilter.neverPassMeasurement` — the guard that keeps the cursor
    /// from sailing past what the head aimed at. On by default; exposed so tests can
    /// show what it is holding back.
    public var neverPassMeasurement: Bool {
        get { filterX.neverPassMeasurement }
        set {
            filterX.neverPassMeasurement = newValue
            filterY.neverPassMeasurement = newValue
        }
    }

    /// Estimated velocity in px/s — diagnostics only.
    public var velocityX: Double { filterX.velocity }
    public var velocityY: Double { filterY.velocity }
    /// Position gain used on the most recent event — diagnostics only.
    public var alphaX: Double { filterX.lastAlpha }
    public var alphaY: Double { filterY.lastAlpha }

    public func configure(_ settings: TremorSettings) {
        filterX.noiseRatio = Self.noiseRatio(forSmoothing: settings.smoothing)
        filterY.noiseRatio = Self.noiseRatio(forSmoothing: settings.effectiveVerticalSmoothing)
    }

    public func reset() {
        filterX.reset()
        filterY.reset()
        rawX = 0; rawY = 0
        prevEstimateX = 0; prevEstimateY = 0
    }

    /// Feed one raw movement (dx, dy) observed over `dt` seconds; returns the
    /// movement to apply for this event.
    public func process(dx: Double, dy: Double, dt: Double = 0) -> (dx: Double, dy: Double) {
        let step = dt > 0 ? dt : Self.nominalDt

        rawX += dx
        rawY += dy

        let estimateX = filterX.update(measurement: rawX, dt: step)
        let estimateY = filterY.update(measurement: rawY, dt: step)

        let outX = estimateX - prevEstimateX
        let outY = estimateY - prevEstimateY
        prevEstimateX = estimateX
        prevEstimateY = estimateY

        return (outX, outY)
    }

    /// Map the 0…1 slider onto the noise ratio. Exponential, so equal slider travel
    /// makes an equally large perceptual difference at both ends — a linear map
    /// crowds all the useful settings into one corner, which is how an earlier
    /// attempt ended up with a slider that appeared to do nothing.
    static func noiseRatio(forSmoothing smoothing: Double) -> Double {
        let s = min(max(smoothing, 0), 1)
        return lightNoiseRatio * pow(heavyNoiseRatio / lightNoiseRatio, s)
    }
}
