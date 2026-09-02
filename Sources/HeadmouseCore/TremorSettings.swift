import Foundation

/// Settings for tremor stabilization (the Stabilization tab). Applied by the app's
/// EventTapFilter through `TremorFilter`.
///
/// Smoothing is **per axis** by design rather than as a later extra: the reference
/// implementation exposes separate horizontal and vertical smoothing, the user runs
/// different values for the two axes in practice, and vertical head movement is
/// measurably shakier than horizontal.
public struct TremorSettings: Codable, Equatable {
    /// Whether stabilization is active.
    public var enabled: Bool

    /// Horizontal smoothing, 0…1. 0 = barely filtered; 1 = very heavy (the estimate
    /// leans hard on the velocity model and averages away almost everything else).
    public var smoothing: Double

    /// Vertical smoothing, 0…1. Ignored while `linkAxes` is true.
    public var verticalSmoothing: Double

    /// When true, the vertical axis uses the horizontal value.
    public var linkAxes: Bool

    /// Diagnostics: append every processed event to `~/hmh-trace.csv`, for recording
    /// the fixtures the offline tuning harness replays. Off in normal use.
    public var trace: Bool

    /// The smoothing actually applied to the vertical axis.
    public var effectiveVerticalSmoothing: Double {
        linkAxes ? smoothing : verticalSmoothing
    }

    public init(
        enabled: Bool = false,
        smoothing: Double = 0.6,
        verticalSmoothing: Double = 0.6,
        linkAxes: Bool = true,
        trace: Bool = false
    ) {
        self.enabled = enabled
        self.smoothing = Self.clamp(smoothing)
        self.verticalSmoothing = Self.clamp(verticalSmoothing)
        self.linkAxes = linkAxes
        self.trace = trace
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TremorSettings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        // `strength` is the old name from the pre-Kalman filters; carry it over so an
        // existing settings.json keeps the user's chosen level instead of resetting.
        let legacyStrength = try c.decodeIfPresent(Double.self, forKey: .strength)
        smoothing = Self.clamp(
            try c.decodeIfPresent(Double.self, forKey: .smoothing) ?? legacyStrength ?? d.smoothing
        )
        verticalSmoothing = Self.clamp(
            try c.decodeIfPresent(Double.self, forKey: .verticalSmoothing) ?? smoothing
        )
        linkAxes = try c.decodeIfPresent(Bool.self, forKey: .linkAxes) ?? d.linkAxes
        trace = try c.decodeIfPresent(Bool.self, forKey: .trace) ?? d.trace
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(smoothing, forKey: .smoothing)
        try c.encode(verticalSmoothing, forKey: .verticalSmoothing)
        try c.encode(linkAxes, forKey: .linkAxes)
        try c.encode(trace, forKey: .trace)
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, smoothing, verticalSmoothing, linkAxes, trace
        case strength   // decode-only, migrated from older builds
    }

    private static func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
}
