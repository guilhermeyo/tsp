import WidgetKit

/// One rendered state of the weather widget.
///
/// The three config values are copied in rather than read from the store by the
/// view, for the same reason `LauncherEntry` copies `apps` and `theme`: a
/// timeline can hold entries for future dates, and a view that read the store
/// at draw time would render whatever the config says THEN, not what the entry
/// was built from.
struct WeatherEntry: TimelineEntry {
    let date: Date
    /// Nil means "no city, and nothing cached" — the only state that shows the
    /// empty label. Every other failure resolves to the last good snapshot
    /// however old it is, because a stale forecast is still information and an
    /// error state is not.
    let snapshot: WeatherSnapshot?
    let theme: Theme
    /// BCP-47, from `config.language`. Weekday abbreviations are formatted with
    /// exactly this and never with the device locale, or the widget would speak
    /// a different language than the app it belongs to.
    let language: String
    let unit: TemperatureUnit
}
