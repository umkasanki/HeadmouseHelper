import Foundation

/// Persists Settings as JSON in Application Support. A custom directory can be
/// injected (used by tests). Never throws to the caller: a missing or corrupt
/// file falls back to defaults, and save errors are surfaced via `lastSaveError`.
public final class SettingsStore {
    private let fileURL: URL

    /// Error from the last save(), if any. nil means the last save succeeded.
    public private(set) var lastSaveError: Error?

    public init(directory: URL? = nil) {
        let dir = directory ?? Self.defaultDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("settings.json")
    }

    private static func defaultDirectory() -> URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("HeadmouseHelper")
    }

    public func load() -> Settings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? Settings.load(from: data) else {
            return Settings()
        }
        return settings
    }

    @discardableResult
    public func save(_ settings: Settings) -> Bool {
        do {
            let data = try settings.jsonData()
            try data.write(to: fileURL, options: .atomic)
            lastSaveError = nil
            return true
        } catch {
            lastSaveError = error
            return false
        }
    }
}
