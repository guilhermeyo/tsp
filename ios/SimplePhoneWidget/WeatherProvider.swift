import WidgetKit

/// Completion-handler `TimelineProvider`, matching `LauncherProvider`'s style.
///
/// The one rule that governs every path here: `completion` must be called
/// exactly once, on every branch including the throw. A provider that returns
/// without completing leaves the system showing its archived snapshot with no
/// timer to replace it, which the user reads as "the widget is broken".
struct WeatherProvider: TimelineProvider {
    /// WidgetKit grants roughly 40-70 provider wake-ups a day. 45 minutes asks
    /// for 32, which fits with headroom; 15 minutes asks for 96, gets
    /// throttled, and produces unpredictable multi-hour gaps — worse refresh
    /// than asking for less.
    private static let refreshInterval: TimeInterval = 45 * 60

    /// Never touches disk or network, by contract: `placeholder` is called on
    /// the render path while the system is deciding what to draw, and it has to
    /// return instantly. The asymmetry with `getSnapshot` below is deliberate
    /// and mirrors `LauncherProvider`'s.
    func placeholder(in context: Context) -> WeatherEntry {
        let config = LauncherConfig.default
        return WeatherEntry(
            date: Date(),
            snapshot: .sample,
            theme: config.theme,
            language: config.language,
            unit: config.weather.unit)
    }

    func getSnapshot(in context: Context, completion: @escaping (WeatherEntry) -> Void) {
        let config = ConfigStore.load()
        // The widget gallery must never show a spinner, an empty box or "set
        // your city": the user is deciding whether to add this thing at all.
        // Outside the gallery, the cache is the honest answer and costs no
        // network.
        let snapshot = context.isPreview ? WeatherSnapshot.sample : WeatherStore.load()
        completion(entry(config: config, snapshot: snapshot, date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeatherEntry>) -> Void) {
        let config = ConfigStore.load()
        let cached = WeatherStore.load()
        let now = Date()

        // `place` is nil until the user picks a city, and on a free personal
        // team it is nil forever because this extension cannot see the app's
        // config at all. Falling back to a real place means the widget shows a
        // real forecast for an obviously-wrong city rather than an empty box —
        // the same bargain `BundledDefaults` makes for the launcher.
        let place = config.weather.place ?? WeatherSettings.fallbackPlace

        // The freshness gate. `ConfigStore.save` calls `reloadAllTimelines()`
        // on every config write in the app, which now also wakes this provider;
        // without this check, changing a font would fire a weather request.
        if let cached, cached.isFresh,
           cached.covers(latitude: place.latitude, longitude: place.longitude) {
            completion(timeline(config: config, snapshot: cached, now: now))
            return
        }

        Task {
            let fetched = try? await WeatherService.fetch(
                latitude: place.latitude,
                longitude: place.longitude,
                placeName: place.name)

            if let fetched { WeatherStore.save(fetched) }

            // `?? cached` even when the cache is for the OLD city. A forecast
            // for the city the user just left is closer to useful than nothing,
            // it is visibly labelled by its own weekdays, and the next refresh
            // replaces it.
            completion(timeline(config: config, snapshot: fetched ?? cached, now: now))
        }
    }

    private func entry(config: LauncherConfig, snapshot: WeatherSnapshot?, date: Date) -> WeatherEntry {
        WeatherEntry(
            date: date,
            snapshot: snapshot,
            theme: config.theme,
            language: config.language,
            unit: config.weather.unit)
    }

    /// One entry for now, plus one at the location's next local midnight when
    /// that falls before the next refresh.
    ///
    /// Extra entries inside a single timeline cost nothing from the wake-up
    /// budget — the system already has the data. That second entry is what
    /// stops the leftmost column from naming yesterday during the gap between
    /// midnight and whenever WidgetKit next feels like waking us.
    private func timeline(config: LauncherConfig, snapshot: WeatherSnapshot?, now: Date) -> Timeline<WeatherEntry> {
        let refreshAt = now.addingTimeInterval(Self.refreshInterval)
        var entries = [entry(config: config, snapshot: snapshot, date: now)]

        if let snapshot,
           let midnight = snapshot.nextMidnight(after: now),
           midnight > now, midnight < refreshAt {
            entries.append(entry(config: config, snapshot: snapshot, date: midnight))
        }

        return Timeline(entries: entries, policy: .after(refreshAt))
    }
}
