import Foundation
import WidgetKit

enum AppGroup {
    static let id = "group.com.guilherme44.simple-phone"
}

/// Single source of truth for the launcher config.
///
/// Writes to the App Group suite when it's available (paid team + entitlement),
/// otherwise falls back to standard `UserDefaults` so the app still works on a
/// free personal team. On a free team the widget lives in a separate sandbox and
/// can't read the app's standard defaults — it shows `BundledDefaults` instead.
enum ConfigStore {
    private static let key = "launcher_config"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: AppGroup.id) ?? .standard
    }

    /// The stored payload, whichever of the two shapes it happens to be in.
    ///
    /// Order matters and is not arbitrary. The original Swift app wrote
    /// `JSONEncoder` output, so on a phone that already has it installed the key
    /// holds a `Data`. The React Native app writes `JSON.stringify` output through
    /// the native bridge, which lands as an `NSString`. Reading `Data` first means
    /// an existing install keeps rendering its real apps until the very first
    /// save from the new app rewrites the key as a string — an in-place upgrade
    /// with no migration step and no window where the widget goes blank.
    ///
    /// `data(forKey:)` returns nil (rather than throwing) when the value is a
    /// string, and `string(forKey:)` returns nil when it is Data, so the two
    /// probes are safe to chain in either order; this order is about which
    /// writer wins during the overlap, not about correctness.
    private static func rawData() -> Data? {
        if let data = defaults.data(forKey: key) { return data }
        if let string = defaults.string(forKey: key) { return string.data(using: .utf8) }
        return nil
    }

    static func load() -> LauncherConfig {
        guard let data = rawData(),
              let config = try? JSONDecoder().decode(LauncherConfig.self, from: data)
        else { return .default }
        return config
    }

    static func save(_ config: LauncherConfig) {
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: key)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
