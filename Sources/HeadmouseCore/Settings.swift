import Foundation

/// Persisted app settings. Decoding is resilient: a file written by an older
/// build that is missing newly-added keys still loads, preserving known values
/// instead of resetting everything to defaults.
public struct Settings: Codable, Equatable {
    /// Desired tracking state. `false` = the user stopped tracking, so the
    /// selected device is seized (cursor frozen). This is what makes the
    /// "stopped" state survive a replug and a reboot.
    public var trackingEnabled: Bool

    /// Remembered device selection, matched by USB vendor/product IDs.
    public var selectedVendorID: Int?
    public var selectedProductID: Int?

    public var launchAtLogin: Bool
    public var notifyOnChange: Bool

    public init(
        trackingEnabled: Bool = true,
        selectedVendorID: Int? = nil,
        selectedProductID: Int? = nil,
        launchAtLogin: Bool = false,
        notifyOnChange: Bool = true
    ) {
        self.trackingEnabled = trackingEnabled
        self.selectedVendorID = selectedVendorID
        self.selectedProductID = selectedProductID
        self.launchAtLogin = launchAtLogin
        self.notifyOnChange = notifyOnChange
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        trackingEnabled = try c.decodeIfPresent(Bool.self, forKey: .trackingEnabled) ?? d.trackingEnabled
        selectedVendorID = try c.decodeIfPresent(Int.self, forKey: .selectedVendorID) ?? d.selectedVendorID
        selectedProductID = try c.decodeIfPresent(Int.self, forKey: .selectedProductID) ?? d.selectedProductID
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        notifyOnChange = try c.decodeIfPresent(Bool.self, forKey: .notifyOnChange) ?? d.notifyOnChange
    }

    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    static func load(from data: Data) throws -> Settings {
        try JSONDecoder().decode(Settings.self, from: data)
    }
}
