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

    static func load() -> LauncherConfig {
        guard let data = defaults.data(forKey: key),
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
