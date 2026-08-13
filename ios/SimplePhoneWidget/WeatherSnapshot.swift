import Foundation

/// One column of the strip: a day, its shape, and how warm it gets.
struct WeatherDay: Codable, Equatable {
    /// Local NOON at the forecast location, never midnight.
    ///
    /// The API gives a bare "2026-08-13" and the day it names is the location's
    /// day, not ours. Anchoring at noon leaves twelve hours of slack in each
    /// direction, so a timezone mistake anywhere downstream — a calendar left
    /// on the device zone, a DST jump, a formatter that forgot — still lands
    /// the weekday label on the right day. Midnight has zero slack in one
    /// direction and is the classic way to render "thu" over Wednesday's data.
    let date: Date
    let condition: WeatherCondition
    /// ALWAYS Celsius. The unit is a display choice applied at render, so
    /// toggling C/F costs no network round trip and cannot invalidate a good
    /// cache.
    let highC: Double
    let lowC: Double
}

/// Everything one fetch produced, and the only thing the cache stores.
struct WeatherSnapshot: Codable, Equatable {
    let placeName: String
    let latitude: Double
    let longitude: Double
    /// The location's offset from UTC, as the API reported it for this
    /// forecast. Stored rather than an IANA name because it is what the
    /// response actually carries, and it is all the calendars below need.
    let utcOffsetSeconds: Int
    /// Nil when the model run had no current reading for this point. Celsius.
    let currentC: Double?
    let currentCondition: WeatherCondition?
    let days: [WeatherDay]
    let fetchedAt: Date

    /// How long a forecast is considered good enough to render without asking
    /// the network again.
    ///
    /// Slightly shorter than the 45-minute refresh policy, so a scheduled wake
    /// always refetches, while the extra wake-ups triggered by
    /// `ConfigStore.save`'s `reloadAllTimelines()` (every config write in the
    /// app now also wakes this provider) cost nothing.
    private static let freshnessWindow: TimeInterval = 40 * 60

    var timeZone: TimeZone {
        TimeZone(secondsFromGMT: utcOffsetSeconds) ?? .current
    }

    /// A calendar pinned to the FORECAST LOCATION, which is the only calendar
    /// any date question here may be asked in. `Calendar.current` in a widget
    /// extension is the device's, and the device is not necessarily where the
    /// weather is.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    var isFresh: Bool {
        let age = Date().timeIntervalSince(fetchedAt)
        // A negative age means the clock moved backwards (timezone change,
        // manual set, NTP correction). Treat it as stale: refetching is cheap,
        // and a snapshot from the future never expires on its own.
        return age >= 0 && age < Self.freshnessWindow
    }

    /// Whether this snapshot is about the place we are being asked to render.
    ///
    /// The freshness gate alone is not enough: a snapshot fetched two minutes
    /// ago for the city the user just changed AWAY from is perfectly fresh and
    /// completely wrong. Two decimals is the precision the request itself is
    /// rounded to, so this compares like with like.
    func covers(latitude: Double, longitude: Double) -> Bool {
        Self.grid(self.latitude) == Self.grid(latitude)
            && Self.grid(self.longitude) == Self.grid(longitude)
    }

    /// Two decimals as an integer, so the comparison never depends on how a
    /// division rounds.
    private static func grid(_ value: Double) -> Int {
        Int((value * 100).rounded())
    }

    /// The columns still worth showing at `date`, oldest first.
    ///
    /// Yesterday's column is not merely useless, it is actively misleading: it
    /// would put the wrong weekday under the leftmost slot, which is the one
    /// glance anybody actually gives this widget.
    func days(from date: Date) -> [WeatherDay] {
        let startOfToday = calendar.startOfDay(for: date)
        return days.filter { $0.date >= startOfToday }
    }

    /// Whether `currentC` may still be shown as "now".
    ///
    /// A current reading is a point in time; the moment the location's day
    /// rolls over, it belongs to a day that is no longer on screen and the
    /// first column has to fall back to that day's high.
    func currentIsValid(at date: Date) -> Bool {
        calendar.isDate(fetchedAt, inSameDayAs: date)
    }

    /// The next local midnight at the forecast location, which is when the
    /// strip has to shift left by one column.
    ///
    /// Computed with calendar arithmetic rather than +86400 so a DST boundary
    /// lands on the real midnight rather than an hour off it.
    func nextMidnight(after date: Date) -> Date? {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
    }

    /// Plausible weather, for `placeholder(in:)` and the widget gallery.
    ///
    /// Built relative to now so the weekday labels read correctly whenever the
    /// gallery is opened; a hardcoded week would show last year's days.
    static let sample: WeatherSnapshot = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()

        let conditions: [WeatherCondition] = [.clear, .partlyCloudy, .cloudy, .rain, .partlyCloudy]
        let highs: [Double] = [28, 26, 24, 22, 25]
        let lows: [Double] = [17, 16, 15, 15, 16]

        let days = (0..<5).map { offset in
            WeatherDay(
                date: calendar.date(byAdding: .day, value: offset, to: noon) ?? noon,
                condition: conditions[offset],
                highC: highs[offset],
                lowC: lows[offset])
        }

        return WeatherSnapshot(
            placeName: WeatherSettings.fallbackPlace.name,
            latitude: WeatherSettings.fallbackPlace.latitude,
            longitude: WeatherSettings.fallbackPlace.longitude,
            utcOffsetSeconds: TimeZone.current.secondsFromGMT(),
            currentC: 24,
            currentCondition: .clear,
            days: days,
            fetchedAt: Date())
    }()
}
