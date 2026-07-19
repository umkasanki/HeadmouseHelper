import Foundation

/// 2D tremor-stabilization filter adapted from opentrack's "accela" filter
/// (© Stanislaw Halik, ISC — see NOTICES.md).
///
/// It keeps a smoothed `output` position and eases it toward the accumulated raw
/// `target` at a velocity given by a nonlinear gain curve of the (dead-zoned,
/// smoothing-scaled) error: small/slow error (tremor) → tiny gain → heavily
/// damped; large/fast error (intent) → high gain → passes through with little
/// lag. Feed relative deltas per event; it returns the smoothed delta to apply.
///
/// Note: the gain curve's domain was tuned by opentrack for head-tracking
/// degrees. For pixel-scale cursor input the effective range is tuned on-device
/// via `smoothing` (and, later, the curve/scale) — this type is the structure.
public final class TremorFilter {
    public var smoothing: Double
    public var deadzone: Double

    private var targetX = 0.0, targetY = 0.0
    private var outputX = 0.0, outputY = 0.0

    /// accela pos_gains: (error distance, gain), ascending by x. Piecewise-linear.
    private static let gains: [(x: Double, y: Double)] = [
        (0, 0), (0.33, 0.375), (0.66, 0.75), (1.33, 2.25), (1.66, 4.5),
        (2, 7.5), (3, 24), (5, 60), (7, 110), (8, 150), (9, 200),
    ]

    public init(smoothing: Double = 1.0, deadzone: Double = 0.1) {
        self.smoothing = smoothing
        self.deadzone = deadzone
    }

    public func configure(_ settings: TremorSettings) {
        smoothing = settings.smoothing
        deadzone = settings.deadzone
    }

    public func reset() {
        targetX = 0; targetY = 0; outputX = 0; outputY = 0
    }

    /// Feed one raw movement (dx, dy) over `dt` seconds; returns the smoothed
    /// movement to apply to the cursor this step.
    public func process(dx: Double, dy: Double, dt: Double) -> (dx: Double, dy: Double) {
        targetX += dx
        targetY += dy

        let s = max(smoothing, 1e-6)
        let ex = deadzoned(targetX - outputX) / s
        let ey = deadzoned(targetY - outputY) / s

        let dist = (ex * ex + ey * ey).squareRoot()
        guard dist > 1e-6 else { return (0, 0) }

        let gain = gainValue(at: dist)

        // Distribute the gain across axes by each axis's share (accela do_deltas).
        var nx = abs(ex) / dist
        var ny = abs(ey) / dist
        let n = nx + ny
        if n > 1e-6 { nx /= n; ny /= n } else { nx = 0; ny = 0 }

        let stepX = (ex < 0 ? -1.0 : 1.0) * nx * gain * dt
        let stepY = (ey < 0 ? -1.0 : 1.0) * ny * gain * dt

        outputX += stepX
        outputY += stepY
        return (stepX, stepY)
    }

    private func deadzoned(_ d: Double) -> Double {
        if abs(d) > deadzone { return d - (d < 0 ? -deadzone : deadzone) }
        return 0
    }

    private func gainValue(at x: Double) -> Double {
        let g = Self.gains
        if x <= g.first!.x { return g.first!.y }
        if x >= g.last!.x { return g.last!.y }
        for i in 1 ..< g.count where x <= g[i].x {
            let a = g[i - 1], b = g[i]
            let t = (x - a.x) / (b.x - a.x)
            return a.y + t * (b.y - a.y)
        }
        return g.last!.y
    }
}
