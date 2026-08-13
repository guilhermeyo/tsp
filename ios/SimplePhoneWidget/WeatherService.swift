import Foundation

/// The one network call this product makes.
///
/// Open-Meteo: no key, no account, no entitlement, HTTPS. That is the whole
/// reason it was chosen over WeatherKit, which needs an entitlement only a paid
/// membership can provision — and a provisioning failure there would break
/// signing for the launcher too.
enum WeatherService {
    enum Failure: Error {
        /// A non-2xx status, or a body that did not parse as the shape below.
        case badResponse
        /// The response parsed but carried no usable day. Rendering an empty
        /// strip over a perfectly good cache would be a downgrade, so this
        /// throws and the provider keeps what it had.
        case emptyForecast
    }

    private static let endpoint = "https://api.open-meteo.com/v1/forecast"

    static func fetch(
        latitude: Double,
        longitude: Double,
        placeName: String
    ) async throws -> WeatherSnapshot {
        var components = URLComponents(string: endpoint)
        components?.queryItems = [
            // Two decimals: about a kilometre, far finer than any forecast
            // model's grid, and it keeps the user's street address out of a
            // third party's request logs. `WeatherSnapshot.covers` compares at
            // exactly this precision, so a cache hit means the same request.
            //
            // `String(format:)` with no locale argument is unlocalized, so the
            // separator is always "." — a comma here would make the API reject
            // the request for every user in a comma-decimal region.
            URLQueryItem(name: "latitude", value: String(format: "%.2f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            // Without this the daily buckets are cut at UTC midnight, which for
            // anyone west of Greenwich shifts every column and makes the last
            // one a day short.
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "5"),
            // Always Celsius on the wire and in the cache; the user's unit is
            // applied at render.
            URLQueryItem(name: "temperature_unit", value: "celsius"),
        ]
        guard let url = components?.url else { throw Failure.badResponse }

        // A widget that hangs is worse than a widget showing yesterday's
        // forecast: while the provider is blocked, the system keeps displaying
        // its archived snapshot, which can be minutes or hours old and has no
        // way to say so. Failing fast into the cache is strictly better.
        //
        // `waitsForConnectivity = false` for the same reason — on a phone with
        // no signal the default would sit and wait for one.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 10
        configuration.waitsForConnectivity = false

        let (data, response) = try await URLSession(configuration: configuration).data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw Failure.badResponse
        }

        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw Failure.badResponse
        }

        return try snapshot(from: payload, latitude: latitude, longitude: longitude, placeName: placeName)
    }

    /// The response, with the JSON keys spelled verbatim.
    ///
    /// snake_case property names and no `CodingKeys`, on purpose: the struct
    /// then diffs by eye against the query string above, and a field renamed on
    /// one side is visible on the other. The conversion to our own names
    /// happens once, below.
    ///
    /// Every value is optional except `daily.time`. Open-Meteo returns nulls at
    /// the edges of a model run, and a single null in a non-optional array
    /// would fail the whole decode and blank the widget.
    private struct Payload: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double?
            let weather_code: Int?
        }

        struct Daily: Decodable {
            let time: [String]
            let weather_code: [Int?]
            let temperature_2m_max: [Double?]
            let temperature_2m_min: [Double?]
        }

        let utc_offset_seconds: Int
        let current: Current?
        let daily: Daily
    }

    private static func snapshot(
        from payload: Payload,
        latitude: Double,
        longitude: Double,
        placeName: String
    ) throws -> WeatherSnapshot {
        let timeZone = TimeZone(secondsFromGMT: payload.utc_offset_seconds) ?? .current

        // en_US_POSIX and an explicit Gregorian calendar, because "yyyy-MM-dd"
        // is a fixed machine format: under a Buddhist or Japanese calendar
        // locale, a default formatter reads the year as an era year and lands
        // centuries away.
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.calendar = Calendar(identifier: .gregorian)
        parser.timeZone = timeZone
        parser.dateFormat = "yyyy-MM-dd"

        // Zipped by the shortest array rather than indexed off `time`. The four
        // arrays are index-aligned in every response seen so far, but indexing
        // on that assumption turns a truncated array into a crash inside the
        // extension, which the user experiences as a permanently blank widget.
        let daily = payload.daily
        let count = min(
            daily.time.count,
            daily.weather_code.count,
            daily.temperature_2m_max.count,
            daily.temperature_2m_min.count)

        var days: [WeatherDay] = []
        for index in 0..<count {
            guard let midnight = parser.date(from: daily.time[index]),
                  let high = daily.temperature_2m_max[index],
                  let low = daily.temperature_2m_min[index]
            else { continue }

            // Local noon. See the comment on `WeatherDay.date`. Twelve hours
            // added to local midnight lands at 11:00 or 13:00 across a DST
            // boundary, which is still unambiguously the same day.
            let noon = midnight.addingTimeInterval(12 * 60 * 60)

            days.append(WeatherDay(
                date: noon,
                condition: WeatherCondition(wmoCode: daily.weather_code[index] ?? -1),
                highC: high,
                lowC: low))
        }

        guard !days.isEmpty else { throw Failure.emptyForecast }

        var currentCondition: WeatherCondition?
        if let code = payload.current?.weather_code {
            currentCondition = WeatherCondition(wmoCode: code)
        }

        return WeatherSnapshot(
            placeName: placeName,
            latitude: latitude,
            longitude: longitude,
            utcOffsetSeconds: payload.utc_offset_seconds,
            currentC: payload.current?.temperature_2m,
            currentCondition: currentCondition,
            days: days,
            fetchedAt: Date())
    }
}
