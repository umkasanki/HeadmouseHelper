import Foundation

/// User-facing cursor-movement tuning, applied to the device via the IOKit
/// pointer properties while tracking is ON. Speed/acceleration technique ported
/// from LinearMouse (MIT).
public struct MovementSettings: Codable, Equatable {
    /// 0…1, higher = faster. Mapped to IOKit pointer resolution.
    public var speed: Double
    /// 0…40 (LinearMouse's range). -1 semantics are expressed via
    /// `disableAcceleration` instead.
    public var acceleration: Double
    /// When true, pointer acceleration is turned off (linear response).
    public var disableAcceleration: Bool

    public init(speed: Double = 0.5, acceleration: Double = 0.6875, disableAcceleration: Bool = false) {
        self.speed = speed.clamped(0, 1)
        self.acceleration = acceleration.clamped(0, 40)
        self.disableAcceleration = disableAcceleration
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MovementSettings()
        speed = (try c.decodeIfPresent(Double.self, forKey: .speed) ?? d.speed).clamped(0, 1)
        acceleration = (try c.decodeIfPresent(Double.self, forKey: .acceleration) ?? d.acceleration).clamped(0, 40)
        disableAcceleration = try c.decodeIfPresent(Bool.self, forKey: .disableAcceleration) ?? d.disableAcceleration
    }

    /// IOKit pointer resolution (lower = faster). Maps speed 0…1 onto the useful
    /// range measured on the device: slow ≈ 1600, fast ≈ 120.
    public var pointerResolution: Double {
        let fast = 120.0, slow = 1600.0
        return slow - speed.clamped(0, 1) * (slow - fast)
    }
}

extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double { min(max(self, lo), hi) }
}
