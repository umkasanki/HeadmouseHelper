import Foundation

/// Which tremor-stabilization algorithm to use. Both preserve the travel distance
/// of deliberate movement (they filter position, not per-event gain), so only
/// jitter is removed and the cursor still reaches its target. Kept as a setting
/// so the two can be A/B compared via presets.
public enum TremorAlgorithm: String, Codable, CaseIterable {
    /// One Euro Filter (Casiez et al., CHI 2012): speed-adaptive low-pass — heavy
    /// smoothing when slow (tremor), light when fast (intent). Recommended.
    case oneEuro
    /// Exponential moving average — a fixed low-pass; simpler but adds constant lag.
    case ewma
}

/// Settings for tremor stabilization (the Stabilization tab). Applied by an
/// event-tap filter (see the app's EventTapFilter) using TremorFilter.
public struct TremorSettings: Codable, Equatable {
    /// Whether stabilization is active.
    public var enabled: Bool
    /// Which algorithm to run.
    public var algorithm: TremorAlgorithm
    /// 0…1 — how strongly to smooth. 0 = barely any effect; 1 = heavy smoothing of
    /// slow movement (maximum tremor suppression).
    public var strength: Double
    /// Per-event movements below this many pixels are suppressed (kills the
    /// smallest sub-pixel jitter). 0 = off.
    public var deadzone: Double

    public init(
        enabled: Bool = false,
        algorithm: TremorAlgorithm = .oneEuro,
        strength: Double = 0.5,
        deadzone: Double = 0
    ) {
        self.enabled = enabled
        self.algorithm = algorithm
        self.strength = min(max(strength, 0), 1)
        self.deadzone = max(0, deadzone)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TremorSettings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        if let raw = try c.decodeIfPresent(String.self, forKey: .algorithm),
           let a = TremorAlgorithm(rawValue: raw) {
            algorithm = a
        } else {
            algorithm = d.algorithm
        }
        strength = min(max(try c.decodeIfPresent(Double.self, forKey: .strength) ?? d.strength, 0), 1)
        deadzone = max(0, try c.decodeIfPresent(Double.self, forKey: .deadzone) ?? d.deadzone)
    }
}
