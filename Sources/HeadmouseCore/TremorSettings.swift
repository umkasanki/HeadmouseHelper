import Foundation

/// Settings for tremor stabilization (the Stabilization tab). Applied by an
/// event-tap filter (see the app's EventTapFilter) using TremorFilter.
public struct TremorSettings: Codable, Equatable {
    /// Whether stabilization is active.
    public var enabled: Bool
    /// Higher = smoother (accela's "sensitivity" divisor): the raw error is
    /// divided by this before the gain curve, so a larger value damps more.
    public var smoothing: Double
    /// Movements below this (in device units) are suppressed entirely — kills
    /// micro-jitter when trying to hold still.
    public var deadzone: Double

    public init(enabled: Bool = false, smoothing: Double = 1.0, deadzone: Double = 0.1) {
        self.enabled = enabled
        self.smoothing = max(0.01, smoothing)
        self.deadzone = max(0, deadzone)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TremorSettings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        smoothing = max(0.01, try c.decodeIfPresent(Double.self, forKey: .smoothing) ?? d.smoothing)
        deadzone = max(0, try c.decodeIfPresent(Double.self, forKey: .deadzone) ?? d.deadzone)
    }
}
