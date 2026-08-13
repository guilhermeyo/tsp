import Foundation

/// The forecast cache: its own key, written only by the widget.
///
/// Deliberately NOT a field inside `launcher_config`. That key belongs to the
/// app, and if this extension wrote to it every fetch would rewrite the user's
/// app list from whatever the widget happened to have decoded — one dropped
/// field away from failure mode #1 in AGENTS.md, arriving through a feature
/// that has nothing to do with apps.
///
/// A separate key also keeps the widget useful when the App Group does not
/// share (free personal team): a cache this process both writes and reads never
/// has to cross the sandbox boundary, so the forecast renders even in the case
/// where `ConfigStore.load()` can only see `BundledDefaults`.
enum WeatherStore {
    private static let key = "weather_cache"

    /// Same fallback as `ConfigStore`: the App Group suite when it is
    /// available, standard defaults otherwise. `AppGroup.id` is defined in
    /// ConfigStore.swift, in this target.
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: AppGroup.id) ?? .standard
    }

    static func load() -> WeatherSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WeatherSnapshot.self, from: data)
    }

    /// No `WidgetCenter.reloadTimelines` here, unlike `ConfigStore.save`.
    /// The only caller is `getTimeline`, which is already inside a reload and
    /// is about to hand back the entry built from this very snapshot; asking
    /// for another one would spend a wake-up from WidgetKit's daily budget to
    /// redraw what is already being drawn.
    static func save(_ snapshot: WeatherSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }
}
