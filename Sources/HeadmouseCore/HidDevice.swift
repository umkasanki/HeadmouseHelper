import Foundation

/// A connected mouse-like HID device, identified by its USB vendor/product IDs.
/// Identity is (vendorID, productID) — enough to remember a personal device and
/// re-match it after a replug.
public struct HidDevice: Codable, Equatable, Identifiable {
    public var vendorID: Int
    public var productID: Int
    public var name: String
    public var manufacturer: String

    /// Stable identity used as a dictionary key and SwiftUI id.
    public var id: String { "\(vendorID):\(productID)" }

    public init(vendorID: Int, productID: Int, name: String, manufacturer: String = "") {
        self.vendorID = vendorID
        self.productID = productID
        self.name = name
        self.manufacturer = manufacturer
    }
}
